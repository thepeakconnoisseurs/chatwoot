# frozen_string_literal: true

require 'rails_helper'

# fork: restrict-waba-templates — request-level send gate, the B1 catcher
# (docs/brief/restrict-waba-templates.md §5, §8). Messages API sends
# template_params top-level; conversations#create nests it under :message —
# both arrive as RAW unpermitted ActionController::Parameters (F4).
RSpec.describe 'Peakwine template send gate', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:custom_role) { create(:custom_role, account: account, permissions: %w[conversation_manage]) }
  let(:restricted_agent) do
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by!(account_id: account.id).update!(custom_role: custom_role)
    user
  end
  let(:contact) { create(:contact, account: account, phone_number: '+6281234567890') }
  let(:inbox) do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    channel.inbox
  end
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:template_name) { 'sample_shipping_confirmation' }
  let(:denied_message) { I18n.t('errors.whatsapp_template_access_denied') }

  before do
    create(:inbox_member, user: restricted_agent, inbox: inbox)
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/{display_id}/messages' do
    let(:messages_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }

    it 'denies an unassigned custom role with 422 and creates no Message row' do
      expect do
        post messages_path,
             params: {
               content: 'forced send',
               message_type: 'outgoing',
               template_params: { name: template_name, language: 'id', namespace: 'ns' }
             },
             headers: restricted_agent.create_new_auth_token,
             as: :json
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(denied_message)
    end

    it 'allows the send once the role is assigned' do
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: template_name, custom_role_id: custom_role.id)

      expect do
        post messages_path,
             params: {
               content: 'allowed send',
               message_type: 'outgoing',
               template_params: { name: template_name, language: 'id', namespace: 'ns' }
             },
             headers: restricted_agent.create_new_auth_token,
             as: :json
      end.to change(Message, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(Message.last.additional_attributes['template_params']['name']).to eq(template_name)
    end

    it 'lets administrators send any template without assignment' do
      expect do
        post messages_path,
             params: {
               content: 'admin send',
               message_type: 'outgoing',
               template_params: { name: template_name, language: 'id' }
             },
             headers: administrator.create_new_auth_token,
             as: :json
      end.to change(Message, :count).by(1)

      expect(response).to have_http_status(:success)
    end

    it 'keeps plain (non-template) sends untouched for the same restricted agent' do
      expect do
        post messages_path,
             params: { content: 'plain reply', message_type: 'outgoing', private: false },
             headers: restricted_agent.create_new_auth_token,
             as: :json
      end.to change(Message, :count).by(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations (nested message params)' do
    let(:conversations_path) { "/api/v1/accounts/#{account.id}/conversations" }

    it 'denies with 422 and rolls back — no orphan conversation is left behind' do
      expect do
        post conversations_path,
             params: {
               inbox_id: inbox.id,
               contact_id: contact.id,
               message: {
                 content: 'forced compose',
                 message_type: 'outgoing',
                 template_params: { name: template_name, language: 'id', namespace: 'ns' }
               }
             },
             headers: restricted_agent.create_new_auth_token,
             as: :json
      end.not_to change(Conversation, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(denied_message)
      expect(Message.count).to eq(0)
    end

    it 'creates the conversation when the role is assigned' do
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: template_name, custom_role_id: custom_role.id)

      expect do
        post conversations_path,
             params: {
               inbox_id: inbox.id,
               contact_id: contact.id,
               message: {
                 content: 'allowed compose',
                 message_type: 'outgoing',
                 template_params: { name: template_name, language: 'id' }
               }
             },
             headers: restricted_agent.create_new_auth_token,
             as: :json
      end.to change(Conversation, :count).by(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes/{inbox.id}/message_templates' do
    it 'returns an empty list for the unassigned custom role (endpoint layer)' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/message_templates",
          headers: restricted_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to eq([])
    end

    it 'returns the full list for administrators' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/message_templates",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].length).to eq(inbox.channel.message_templates.length)
    end

    it 'returns only assigned names once a role is assigned' do
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: template_name, custom_role_id: custom_role.id)

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/message_templates",
          headers: restricted_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      names = response.parsed_body['payload'].pluck('name').uniq
      expect(names).to eq([template_name])
    end

    it 'does NOT filter Twilio WhatsApp templates for a restricted agent (B3 guard — Cloud-only filter)' do
      twilio_channel = create(:channel_twilio_sms, :whatsapp, account: account,
                                                              content_templates: { 'templates' => [{ 'friendly_name' => 'order_update' }] })
      twilio_inbox = twilio_channel.inbox
      create(:inbox_member, user: restricted_agent, inbox: twilio_inbox)

      get "/api/v1/accounts/#{account.id}/inboxes/#{twilio_inbox.id}/message_templates",
          headers: restricted_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].length).to eq(1)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes (inbox payload layer, web + mobile)' do
    it 'empties message_templates in the inbox payload for the unassigned custom role' do
      get "/api/v1/accounts/#{account.id}/inboxes",
          headers: restricted_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      whatsapp_payload = response.parsed_body['payload'].find { |record| record['id'] == inbox.id }
      expect(whatsapp_payload['message_templates']).to eq([])
    end

    it 'keeps the full list for administrators' do
      get "/api/v1/accounts/#{account.id}/inboxes",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      whatsapp_payload = response.parsed_body['payload'].find { |record| record['id'] == inbox.id }
      expect(whatsapp_payload['message_templates'].length).to eq(inbox.channel.message_templates.length)
    end
  end
end
