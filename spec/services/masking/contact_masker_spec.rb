# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Masking::ContactMasker do
  describe '.mask_phone' do
    it 'keeps the first 6 characters and appends exactly 5 stars' do
      expect(described_class.mask_phone('+6282121550730')).to eq('+62821*****')
    end

    it 'masks short strings with the fixed star count' do
      expect(described_class.mask_phone('62')).to eq('62*****')
    end

    it 'strips surrounding whitespace before masking' do
      expect(described_class.mask_phone('  +628123456789  ')).to eq('+62812*****')
    end

    it 'returns nil and blank values as-is' do
      expect(described_class.mask_phone(nil)).to be_nil
      expect(described_class.mask_phone('')).to eq('')
      expect(described_class.mask_phone('   ')).to eq('   ')
    end
  end

  describe '.mask_email' do
    it 'keeps the first 2 local characters, adds *** and the full domain' do
      expect(described_class.mask_email('peakwine@gmail.com')).to eq('pe***@gmail.com')
    end

    it 'keeps a single-character local part as-is plus the stars' do
      expect(described_class.mask_email('a@gmail.com')).to eq('a***@gmail.com')
    end

    it 'returns strings without an @ as-is' do
      expect(described_class.mask_email('not-an-email')).to eq('not-an-email')
    end

    it 'returns nil and blank values as-is' do
      expect(described_class.mask_email(nil)).to be_nil
      expect(described_class.mask_email('')).to eq('')
    end
  end

  describe '.mask_name_if_phone' do
    it 'keeps regular names untouched' do
      expect(described_class.mask_name_if_phone('Tridi')).to eq('Tridi')
    end

    it 'masks plus-prefixed phone-like names' do
      expect(described_class.mask_name_if_phone('+62 812-345')).to eq('+62 81*****')
    end

    it 'masks plain digit names' do
      expect(described_class.mask_name_if_phone('08123456789')).to eq('081234*****')
    end

    it 'returns nil as-is' do
      expect(described_class.mask_name_if_phone(nil)).to be_nil
    end
  end

  describe '.mask_source_id' do
    it 'masks phone-like source ids' do
      expect(described_class.mask_source_id('6281234567890')).to eq('628123*****')
    end

    it 'masks email-based source ids like an email' do
      expect(described_class.mask_source_id('someone@example.com')).to eq('so***@example.com')
    end

    it 'keeps uuid-like source ids untouched' do
      uuid = SecureRandom.uuid
      expect(described_class.mask_source_id(uuid)).to eq(uuid)
    end

    it 'returns nil as-is' do
      expect(described_class.mask_source_id(nil)).to be_nil
    end
  end

  describe '.restricted?' do
    let(:account) { create(:account) }

    it 'treats a missing viewer (job/websocket context) as restricted' do
      expect(described_class.restricted?(nil)).to be(true)
    end

    it 'treats administrators as unrestricted' do
      admin = create(:account_user, account: account, role: :administrator)

      expect(described_class.restricted?(admin)).to be(false)
    end

    it 'treats agents without a custom role as unrestricted' do
      agent = create(:account_user, account: account, role: :agent)

      expect(described_class.restricted?(agent)).to be(false)
    end

    it 'treats custom-role agents without contact_manage as restricted' do
      custom_role = create(:custom_role, account: account, permissions: %w[conversation_manage])
      agent = create(:account_user, account: account, role: :agent, custom_role: custom_role)

      expect(described_class.restricted?(agent)).to be(true)
    end

    it 'treats custom-role agents holding contact_manage as unrestricted' do
      custom_role = create(:custom_role, account: account, permissions: %w[contact_manage report_manage])
      agent = create(:account_user, account: account, role: :agent, custom_role: custom_role)

      expect(described_class.restricted?(agent)).to be(false)
    end

    it 'treats a custom-role agent whose role record was deleted as restricted' do
      custom_role = create(:custom_role, account: account, permissions: %w[conversation_manage])
      agent = create(:account_user, account: account, role: :agent, custom_role: custom_role)
      agent.update(custom_role_id: CustomRole.last.id + 1)

      expect(described_class.restricted?(agent.reload)).to be(true)
    end
  end
end
