require 'rails_helper'

RSpec.describe 'Contact PII masking', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:custom_role) { create(:custom_role, account: account, permissions: %w[conversation_manage]) }
  let(:restricted_agent) do
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by!(account_id: account.id).update!(custom_role: custom_role)
    user
  end
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
  let!(:contact_inbox) { conversation.contact_inbox }

  before do
    create(:inbox_member, user: restricted_agent, inbox: inbox)
    create(:message, conversation: conversation, account: account, sender: contact, content: 'masking fixture message')
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts' do
    it 'masks phone, email, phone-like name and source_id for restricted agents' do
      get "/api/v1/accounts/#{account.id}/contacts",
          headers: restricted_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      contact_payload = payload.find { |record| record['id'] == contact.id }
      expect(contact_payload['phone_number']).to eq('+62812*****')
      expect(contact_payload['email']).to eq('pe***@gmail.com')
      expect(contact_payload['name']).to eq('+62812*****')
      source_ids = contact_payload['contact_inboxes'].pluck('source_id')
      expect(source_ids).to include(Masking::ContactMasker.mask_source_id(contact_inbox.source_id))
      expect(source_ids).not_to include(contact_inbox.source_id)
    end

    it 'returns raw values for administrators' do
      contact
      conversation

      get "/api/v1/accounts/#{account.id}/contacts",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      contact_payload = response.parsed_body['payload'].find { |record| record['id'] == contact.id }
      expect(contact_payload['phone_number']).to eq(contact.phone_number)
      expect(contact_payload['email']).to eq(contact.email)
      expect(contact_payload['name']).to eq(contact.name)
      expect(contact_payload['contact_inboxes'].pluck('source_id')).to include(contact_inbox.source_id)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id' do
    it 'masks PII for restricted agents' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          headers: restricted_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload['phone_number']).to eq('+62812*****')
      expect(payload['email']).to eq('pe***@gmail.com')
      expect(payload['name']).to eq('+62812*****')
    end

    it 'returns raw values for administrators' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload['phone_number']).to eq(contact.phone_number)
      expect(payload['email']).to eq(contact.email)
      expect(payload['name']).to eq(contact.name)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/search' do
    it 'finds the contact by the full original number and masks it for restricted agents' do
      get "/api/v1/accounts/#{account.id}/contacts/search",
          params: { q: '6281234567890' },
          headers: restricted_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.pluck('id')).to include(contact.id)
      contact_payload = payload.find { |record| record['id'] == contact.id }
      expect(contact_payload['phone_number']).to eq('+62812*****')
      expect(contact_payload['email']).to eq('pe***@gmail.com')
      expect(contact_payload['name']).to eq('+62812*****')
    end

    it 'returns raw values for administrators' do
      get "/api/v1/accounts/#{account.id}/contacts/search",
          params: { q: '6281234567890' },
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      contact_payload = response.parsed_body['payload'].find { |record| record['id'] == contact.id }
      expect(contact_payload['phone_number']).to eq(contact.phone_number)
      expect(contact_payload['email']).to eq(contact.email)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id/contactable_inboxes' do
    it 'is denied for restricted agents (compose flow)' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes",
          headers: restricted_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns raw source_id for administrators' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('source_id')).to include(contact.phone_number.delete('+'))
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/search' do
    it 'masks the contact name for restricted agents' do
      get "/api/v1/accounts/#{account.id}/conversations/search",
          params: { q: 'masking fixture' },
          headers: restricted_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      conversation_payload = payload.find { |record| record['id'] == conversation.display_id }
      expect(conversation_payload['contact']['name']).to eq('+62812*****')
    end

    it 'returns the raw contact name for administrators' do
      get "/api/v1/accounts/#{account.id}/conversations/search",
          params: { q: 'masking fixture' },
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      conversation_payload = payload.find { |record| record['id'] == conversation.display_id }
      expect(conversation_payload['contact']['name']).to eq(contact.name)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations' do
    it 'masks the contact sender and source_id for restricted agents' do
      get "/api/v1/accounts/#{account.id}/conversations",
          headers: restricted_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['data']['payload']
      conversation_payload = payload.find { |record| record['id'] == conversation.display_id }
      sender = conversation_payload['meta']['sender']
      expect(sender['phone_number']).to eq('+62812*****')
      expect(sender['email']).to eq('pe***@gmail.com')
      expect(sender['name']).to eq('+62812*****')

      message = conversation_payload['messages'].first
      expect(message['sender']['phone_number']).to eq('+62812*****')
      expect(message['conversation']['contact_inbox']['source_id']).to eq(Masking::ContactMasker.mask_source_id(contact_inbox.source_id))
    end

    it 'returns raw values for administrators' do
      get "/api/v1/accounts/#{account.id}/conversations",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['data']['payload']
      conversation_payload = payload.find { |record| record['id'] == conversation.display_id }
      sender = conversation_payload['meta']['sender']
      expect(sender['phone_number']).to eq(contact.phone_number)
      expect(sender['email']).to eq(contact.email)
      expect(sender['name']).to eq(contact.name)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/:id' do
    it 'masks the contact sender for restricted agents' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
          headers: restricted_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      sender = response.parsed_body['meta']['sender']
      expect(sender['phone_number']).to eq('+62812*****')
      expect(sender['email']).to eq('pe***@gmail.com')
    end

    it 'returns raw values for administrators' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      sender = response.parsed_body['meta']['sender']
      expect(sender['phone_number']).to eq(contact.phone_number)
      expect(sender['email']).to eq(contact.email)
    end
  end

  describe 'widget and public API responses stay raw' do
    let(:web_widget) { create(:channel_widget, account: account) }
    let(:widget_contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
    let(:widget_conversation) do
      create(:conversation, account: account, contact: contact, inbox: web_widget.inbox, contact_inbox: widget_contact_inbox)
    end
    let(:widget_token) do
      Widget::TokenService.new(payload: { source_id: widget_contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
    end

    before do
      create(:message, account: account, inbox: web_widget.inbox, conversation: widget_conversation, sender: contact)
    end

    it 'returns the raw contact sender in widget messages despite the nil viewer context' do
      get api_v1_widget_messages_url,
          params: { website_token: web_widget.website_token },
          headers: { 'X-Auth-Token' => widget_token },
          as: :json

      expect(response).to have_http_status(:success)
      senders = response.parsed_body['payload'].filter_map { |message| message['sender'] }
      expect(senders).not_to be_empty
      expect(senders.pluck('phone_number')).to all(eq(contact.phone_number))
      expect(senders.pluck('email')).to all(eq(contact.email))
    end

    it 'returns the raw contact sender in public inbox messages despite the nil viewer context' do
      api_channel = create(:channel_api, account: account)
      public_contact_inbox = create(:contact_inbox, contact: contact, inbox: api_channel.inbox)
      public_conversation = create(:conversation, account: account, contact: contact,
                                                  inbox: api_channel.inbox, contact_inbox: public_contact_inbox)
      create(:message, account: account, inbox: api_channel.inbox, conversation: public_conversation, sender: contact)

      get "/public/api/v1/inboxes/#{api_channel.identifier}/contacts/#{public_contact_inbox.source_id}" \
          "/conversations/#{public_conversation.display_id}/messages"

      expect(response).to have_http_status(:success)
      senders = response.parsed_body.filter_map { |message| message['sender'] }
      expect(senders).not_to be_empty
      expect(senders.pluck('phone_number')).to all(eq(contact.phone_number))
      expect(senders.pluck('email')).to all(eq(contact.email))
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts/export' do
    it 'is denied for restricted agents' do
      allow(Account::ContactsExportJob).to receive(:perform_later)

      post "/api/v1/accounts/#{account.id}/contacts/export",
           headers: restricted_agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Account::ContactsExportJob).not_to have_received(:perform_later)
    end

    it 'succeeds for administrators' do
      allow(Account::ContactsExportJob).to receive(:perform_later)

      post "/api/v1/accounts/#{account.id}/contacts/export",
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(Account::ContactsExportJob).to have_received(:perform_later)
    end
  end
end
