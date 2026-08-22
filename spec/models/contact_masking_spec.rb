require 'rails_helper'

RSpec.describe Contact do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, :with_email, account: account, name: '+6281234567890',
                                  phone_number: '+6281234567890', email: 'peakwine@gmail.com')
  end
  let(:inbox) do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    channel.inbox
  end
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:restricted_account_user) do
    custom_role = create(:custom_role, account: account, permissions: %w[conversation_manage])
    create(:account_user, account: account, role: :agent, custom_role: custom_role)
  end

  before { Current.account_user = nil }

  after { Current.reset }

  describe 'Contact#push_event_data' do
    it 'masks name-if-phone, phone_number and email when no viewer context exists (job/websocket)' do
      data = contact.push_event_data

      expect(data[:name]).to eq('+62812*****')
      expect(data[:phone_number]).to eq('+62812*****')
      expect(data[:email]).to eq('pe***@gmail.com')
      expect(data[:additional_attributes]).to eq(contact.additional_attributes)
    end

    it 'keeps the payload shape unchanged' do
      expect(contact.push_event_data.keys).to contain_exactly(
        :additional_attributes, :custom_attributes, :email, :id, :identifier,
        :name, :phone_number, :thumbnail, :blocked, :type
      )
    end

    it 'masks for a restricted account user in request context' do
      Current.account_user = restricted_account_user

      expect(contact.push_event_data[:phone_number]).to eq('+62812*****')
    end

    it 'stays raw when built with masked: false (webhook builders)' do
      data = contact.push_event_data(masked: false)

      expect(data[:name]).to eq(contact.name)
      expect(data[:phone_number]).to eq(contact.phone_number)
      expect(data[:email]).to eq(contact.email)
    end
  end

  describe 'Conversations::EventDataPresenter' do
    let(:presenter) { Conversations::EventDataPresenter.new(conversation) }

    it 'masks the sender and the contact_inbox source_id in push_data when no viewer context exists' do
      data = presenter.push_data

      expect(data[:meta][:sender][:phone_number]).to eq('+62812*****')
      expect(data[:meta][:sender][:email]).to eq('pe***@gmail.com')
      expect(data[:contact_inbox]).to be_a(Hash)
      expect(data[:contact_inbox][:source_id]).to eq(Masking::ContactMasker.mask_source_id(conversation.contact_inbox.source_id))
    end

    it 'keeps webhook_data raw (sender + contact_inbox) even for a restricted viewer' do
      Current.account_user = restricted_account_user
      data = presenter.webhook_data

      expect(data[:meta][:sender][:phone_number]).to eq(contact.phone_number)
      expect(data[:meta][:sender][:email]).to eq(contact.email)
      expect(data[:meta][:sender][:name]).to eq(contact.name)
      expect(data[:contact_inbox][:source_id]).to eq(conversation.contact_inbox.source_id)
    end
  end

  describe 'Notification#push_message_body' do
    let(:message) { create(:message, conversation: conversation, account: account, sender: contact) }
    let(:notification) do
      create(:notification, account: account, notification_type: 'conversation_creation',
                            primary_actor: conversation, secondary_actor: message)
    end

    before { conversation.messages << message }

    it 'masks phone-like contact sender names when no viewer context exists (job context)' do
      notification.reload

      expect(notification.push_message_body).to start_with('+62812*****:')
    end

    it 'keeps the sender name raw for an administrator viewer' do
      Current.account_user = create(:account_user, account: account, role: :administrator)
      notification.reload

      expect(notification.push_message_body).to start_with("#{contact.name}:")
    end
  end

  describe 'Message#push_event_data' do
    let!(:message) { create(:message, conversation: conversation, account: account, sender: contact) }

    it 'masks the sender and the conversation contact_inbox source_id when no viewer context exists' do
      data = message.push_event_data

      expect(data[:sender][:phone_number]).to eq('+62812*****')
      expect(data[:sender][:email]).to eq('pe***@gmail.com')
      expect(data[:conversation][:contact_inbox][:source_id]).to eq(Masking::ContactMasker.mask_source_id(conversation.contact_inbox.source_id))
    end

    it 'keeps webhook_push_event_data raw' do
      data = message.webhook_push_event_data

      expect(data[:sender][:phone_number]).to eq(contact.phone_number)
      expect(data[:sender][:email]).to eq(contact.email)
      expect(data[:conversation][:contact_inbox][:source_id]).to eq(conversation.contact_inbox.source_id)
    end
  end
end
