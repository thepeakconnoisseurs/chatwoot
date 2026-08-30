# frozen_string_literal: true

require 'rails_helper'

# fork: restrict-waba-templates — validasi model ACL (docs/brief/restrict-waba-templates.md §4.2)
RSpec.describe Peakwine::TemplatePermission do
  let(:account) { create(:account) }
  let(:custom_role) { create(:custom_role, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }

  describe 'validations' do
    it 'is valid with an account, a Cloud WA inbox, a template name and an account role' do
      permission = described_class.new(
        account: account, inbox: inbox,
        template_name: 'sample_shipping_confirmation', custom_role_id: custom_role.id
      )

      expect(permission).to be_valid
    end

    it 'rejects a blank template name' do
      permission = described_class.new(
        account: account, inbox: inbox,
        template_name: '', custom_role_id: custom_role.id
      )

      expect(permission).not_to be_valid
      expect(permission.errors[:template_name]).to be_present
    end

    it 'rejects a custom role from another account' do
      other_role = create(:custom_role, account: create(:account))
      permission = described_class.new(
        account: account, inbox: inbox,
        template_name: 'x', custom_role_id: other_role.id
      )

      expect(permission).not_to be_valid
      expect(permission.errors[:custom_role_id]).to be_present
    end

    it 'fails as a validation error (not NoMethodError/500) when the EE custom_roles association is absent' do
      allow(account).to receive(:respond_to?) { |name| name != :custom_roles }
      permission = described_class.new(
        account: account, inbox: inbox,
        template_name: 'x', custom_role_id: custom_role.id
      )

      expect(permission).not_to be_valid
      expect(permission.errors[:custom_role_id]).to be_present
    end

    it 'rejects a non Cloud-WhatsApp inbox' do
      web_inbox = create(:inbox, account: account)
      permission = described_class.new(
        account: account, inbox: web_inbox,
        template_name: 'x', custom_role_id: custom_role.id
      )

      expect(permission).not_to be_valid
      expect(permission.errors[:inbox_id]).to be_present
    end

    it 'enforces uniqueness of (inbox, template_name, custom_role_id)' do
      described_class.create!(
        account: account, inbox: inbox,
        template_name: 'x', custom_role_id: custom_role.id
      )
      duplicate = described_class.new(
        account: account, inbox: inbox,
        template_name: 'x', custom_role_id: custom_role.id
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:custom_role_id]).to be_present
    end
  end

  describe 'FK cascade (audits R1/R2, edge cases E11/E12)' do
    it 'removes assignment rows when the custom role is deleted' do
      permission = described_class.create!(
        account: account, inbox: inbox,
        template_name: 'x', custom_role_id: custom_role.id
      )

      expect { custom_role.destroy }.to change(described_class, :count).by(-1)
      expect(described_class.exists?(permission.id)).to be(false)
    end

    it 'removes assignment rows when the inbox is deleted' do
      permission = described_class.create!(
        account: account, inbox: inbox,
        template_name: 'x', custom_role_id: custom_role.id
      )

      expect { inbox.destroy }.to change(described_class, :count).by(-1)
      expect(described_class.exists?(permission.id)).to be(false)
    end
  end
end
