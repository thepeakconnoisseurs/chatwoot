# frozen_string_literal: true

require 'rails_helper'

# fork: restrict-waba-templates — admin-only CRUD assignment (docs/brief/restrict-waba-templates.md §6 T6)
RSpec.describe 'Peakwine template permissions CRUD', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:custom_role) { create(:custom_role, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:base_path) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/template_permissions" }

  # unique names present in the channel_whatsapp factory payload
  let(:channel_names) do
    channel.message_templates.filter_map { |template| template['name'] }.uniq
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes/{inbox.id}/template_permissions' do
    it 'denies non-administrators (Pundit → render_unauthorized)' do
      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists every channel template with its role_ids and reports orphan names' do
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: 'sample_shipping_confirmation', custom_role_id: custom_role.id)
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: 'gone_from_meta', custom_role_id: custom_role.id)

      get base_path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.pluck('template_name')).to match_array(channel_names)
      shipping = payload.find { |entry| entry['template_name'] == 'sample_shipping_confirmation' }
      expect(shipping['role_ids']).to eq([custom_role.id])
      expect(payload.pluck('template_name')).not_to include('gone_from_meta')
      expect(response.parsed_body['meta']['orphan_names']).to eq(['gone_from_meta'])
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/inboxes/{inbox.id}/template_permissions' do
    it 'denies non-administrators' do
      put base_path,
          params: { template_permissions: [{ template_name: 'sample_shipping_confirmation', role_ids: [custom_role.id] }] },
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'replaces all assignments atomically (delete_all + insert) → 204' do
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: 'customer_yes_no', custom_role_id: custom_role.id)

      put base_path,
          params: { template_permissions: [
            { template_name: 'sample_shipping_confirmation', role_ids: [custom_role.id] },
            { template_name: 'customer_yes_no', role_ids: [] }
          ] },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      rows = Peakwine::TemplatePermission.for_inbox(inbox)
      expect(rows.count).to eq(1)
      expect(rows.first.template_name).to eq('sample_shipping_confirmation')
      expect(rows.first.custom_role_id).to eq(custom_role.id)
    end

    it 'rejects a template name that is not on the channel' do
      put base_path,
          params: { template_permissions: [{ template_name: 'not_on_channel', role_ids: [custom_role.id] }] },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Peakwine::TemplatePermission.for_inbox(inbox)).to be_empty
    end

    it 'rejects a role from another account and keeps existing rows (atomic rollback)' do
      other_account_role = create(:custom_role, account: create(:account))
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: 'customer_yes_no', custom_role_id: custom_role.id)

      put base_path,
          params: { template_permissions: [
            { template_name: 'customer_yes_no', role_ids: [custom_role.id, other_account_role.id] }
          ] },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      rows = Peakwine::TemplatePermission.for_inbox(inbox)
      expect(rows.count).to eq(1)
      expect(rows.first.template_name).to eq('customer_yes_no')
    end

    it 'cleans up orphan rows via replace-all with empty role_ids' do
      create(:peakwine_template_permission, account: account, inbox: inbox,
                                            template_name: 'gone_from_meta', custom_role_id: custom_role.id)

      put base_path,
          params: { template_permissions: [{ template_name: 'gone_from_meta', role_ids: [] }] },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(Peakwine::TemplatePermission.for_inbox(inbox)).to be_empty
    end
  end
end
