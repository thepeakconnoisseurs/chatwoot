# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V2::Reports::DrilldownRecordSerializer do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, :with_email, account: account, name: '+6281234567890',
                                  phone_number: '+6281234567890', email: 'peakwine@gmail.com')
  end
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:serializer) { described_class.new(account, 'conversations_count', false, [conversation]) }

  after { Current.reset }

  it 'masks the contact name for a restricted viewer' do
    custom_role = create(:custom_role, account: account, permissions: %w[conversation_manage])
    Current.account_user = create(:account_user, account: account, role: :agent, custom_role: custom_role)

    expect(serializer.serialize(conversation)[:conversation][:contact_name]).to eq('+62812*****')
  end

  it 'keeps the contact name raw without masking for an administrator' do
    Current.account_user = create(:account_user, account: account, role: :administrator)

    expect(serializer.serialize(conversation)[:conversation][:contact_name]).to eq(contact.name)
  end
end
