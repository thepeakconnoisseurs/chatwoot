require 'rails_helper'

RSpec.describe 'Campaign analytics API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago) }
  let(:delivered_contact) { create(:contact, :with_phone_number, account: account) }
  let(:read_contact) { create(:contact, :with_phone_number, account: account) }
  let(:failed_contact) { create(:contact, :with_phone_number, account: account) }
  let(:skipped_contact) { create(:contact, account: account) }

  before do
    account.enable_features!(:whatsapp_campaign)
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: delivered_contact,
                              status: :delivered, source_id: 'wamid.delivered')
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: read_contact,
                              status: :read, source_id: 'wamid.read')
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: failed_contact, status: :failed)
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: skipped_contact, status: :skipped)
  end

  describe 'GET /api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/metrics' do
    it 'returns cumulative metrics and exact status counts' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'audience' => 4,
        'sent' => 2,
        'delivered' => 2,
        'read' => 1,
        'failed' => 1,
        'skipped' => 1,
        'status_counts' => include('delivered' => 1, 'read' => 1, 'failed' => 1, 'skipped' => 1)
      )
    end

    it 'requires the WhatsApp campaign feature' do
      account.disable_features!(:whatsapp_campaign)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires campaign access' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/contacts' do
    it 'filters and paginates recipients by exact status' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/contacts",
          params: { status: 'read', page: 1 },
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to contain_exactly(
        include('contact' => include('id' => read_contact.id), 'status' => 'read')
      )
      expect(response.parsed_body['meta']).to include('current_page' => 1, 'total_pages' => 1, 'total_count' => 1)
    end

    context 'when the viewer is a restricted agent' do
      let(:restricted_agent) do
        custom_role = create(:custom_role, account: account, permissions: %w[conversation_manage])
        user = create(:user, account: account, role: :agent)
        user.account_users.find_by!(account_id: account.id).update!(custom_role: custom_role)
        user
      end

      before do
        delivered_contact.update!(name: '+6281234567890')
      end

      it 'masks the contact name and phone number' do
        # The campaign policy is admin-only today; exercise the payload masking
        # for a restricted viewer in case the access rule is ever relaxed.
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(CampaignPolicy).to receive(:show?).and_return(true)
        # rubocop:enable RSpec/AnyInstance
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/contacts",
            params: { status: 'delivered', page: 1 },
            headers: restricted_agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        contact_payload = response.parsed_body['payload'].first['contact']
        expect(contact_payload['name']).to eq('+62812*****')
        expect(contact_payload['phone_number']).to eq(Masking::ContactMasker.mask_phone(delivered_contact.phone_number))
      end
    end
  end
end
