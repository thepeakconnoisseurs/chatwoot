# frozen_string_literal: true

require 'rails_helper'

# fork: restrict-waba-templates — spec cermin untuk helper tunggal
# (docs/brief/restrict-waba-templates.md §5, §8).
RSpec.describe Peakwine::TemplateAccess do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:custom_role) { create(:custom_role, account: account, permissions: %w[conversation_manage]) }
  let(:assigned_agent) do
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by!(account_id: account.id).update!(custom_role: custom_role)
    user
  end
  let(:plain_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    channel.inbox
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:template_name) { 'sample_shipping_confirmation' }

  let(:admin_account_user) { administrator.account_users.find_by!(account_id: account.id) }
  let(:agent_account_user) { assigned_agent.account_users.find_by!(account_id: account.id) }
  let(:plain_account_user) { plain_agent.account_users.find_by!(account_id: account.id) }

  def assign_template!(name: template_name, role: custom_role, account_user: agent_account_user)
    create(:peakwine_template_permission, account: account, inbox: inbox,
                                          template_name: name, custom_role: role)
    account_user # noop, kept for readability at call sites
  end

  describe '.allowed?' do
    it 'allows administrators without any assignment' do
      expect(described_class.allowed?(admin_account_user, inbox, template_name)).to be(true)
    end

    it 'allows a custom role with a matching assignment' do
      assign_template!

      expect(described_class.allowed?(agent_account_user, inbox, template_name)).to be(true)
    end

    it 'denies a custom role without a matching assignment (default-deny)' do
      expect(described_class.allowed?(agent_account_user, inbox, template_name)).to be(false)
    end

    it 'denies an agent without a custom role' do
      expect(described_class.allowed?(plain_account_user, inbox, template_name)).to be(false)
    end

    it 'denies a missing viewer (job/websocket context)' do
      expect(described_class.allowed?(nil, inbox, template_name)).to be(false)
    end

    it 'denies a blank template name' do
      expect(described_class.allowed?(agent_account_user, inbox, nil)).to be(false)
      expect(described_class.allowed?(agent_account_user, inbox, '')).to be(false)
    end

    it 'is inbox-scoped: an assignment on another inbox does not leak' do
      other_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                sync_templates: false, validate_provider_config: false)
      assign_template!
      other_channel.inbox # ensure it exists

      expect(described_class.allowed?(agent_account_user, other_channel.inbox, template_name)).to be(false)
    end
  end

  describe '.filter_templates' do
    let(:templates) do
      [
        { 'name' => 'sample_shipping_confirmation', 'language' => 'id' },
        { 'name' => 'sample_shipping_confirmation', 'language' => 'en_US' },
        { 'name' => 'customer_yes_no', 'language' => 'ar' },
        { 'name' => 'ticket_status_updated', 'language' => 'en' }
      ]
    end

    it 'returns the full list for administrators' do
      expect(described_class.filter_templates(admin_account_user, inbox, templates)).to eq(templates)
    end

    it 'returns [] for a missing viewer' do
      expect(described_class.filter_templates(nil, inbox, templates)).to eq([])
    end

    it 'returns [] for an agent without a custom role' do
      expect(described_class.filter_templates(plain_account_user, inbox, templates)).to eq([])
    end

    it 'returns only assigned names — language-agnostic by name' do
      assign_template!(name: 'sample_shipping_confirmation')

      filtered = described_class.filter_templates(agent_account_user, inbox, templates)
      expect(filtered.map { |template| template['name'] }).to eq(%w[sample_shipping_confirmation sample_shipping_confirmation])
    end

    it 'returns non-array input untouched' do
      expect(described_class.filter_templates(agent_account_user, inbox, nil)).to be_nil
      expect(described_class.filter_templates(agent_account_user, inbox, 'nope')).to eq('nope')
    end
  end

  describe '.enforce_send!' do
    let(:template_params) { { name: template_name, language: 'id', namespace: 'ns' } }

    it 'raises Denied with the localized message for an unassigned custom role' do
      expect { described_class.enforce_send!(assigned_agent, conversation, template_params) }
        .to raise_error(Peakwine::TemplateAccess::Denied, I18n.t('errors.whatsapp_template_access_denied'))
    end

    it 'allows a custom role with a matching assignment' do
      assign_template!

      expect { described_class.enforce_send!(assigned_agent, conversation, template_params) }.not_to raise_error
    end

    it 'allows administrators' do
      expect { described_class.enforce_send!(administrator, conversation, template_params) }.not_to raise_error
    end

    it 'allows an AgentBot instance (mandatory bypass — no account_users assoc, F15)' do
      agent_bot = create(:agent_bot)

      expect { described_class.enforce_send!(agent_bot, conversation, template_params) }.not_to raise_error
    end

    it 'allows when automation: is set (admin-configured rule, F16)' do
      expect { described_class.enforce_send!(assigned_agent, conversation, template_params, automation: true) }.not_to raise_error
    end

    it 'is a no-op without template params (automation/campaign builder call with user=nil)' do
      expect { described_class.enforce_send!(nil, conversation, nil) }.not_to raise_error
      expect { described_class.enforce_send!(nil, conversation, {}) }.not_to raise_error
    end

    it 'denies a nil user when a template name IS present (no NoMethodError → 500)' do
      expect { described_class.enforce_send!(nil, conversation, template_params) }
        .to raise_error(Peakwine::TemplateAccess::Denied, I18n.t('errors.whatsapp_template_access_denied'))
    end

    it 'is a no-op on Twilio WhatsApp inboxes — gate is Cloud-only (E10/F18)' do
      twilio_channel = create(:channel_twilio_sms, :whatsapp, account: account)
      twilio_conversation = create(:conversation, account: account, inbox: twilio_channel.inbox)

      expect { described_class.enforce_send!(assigned_agent, twilio_conversation, template_params) }.not_to raise_error
    end

    it 'denies a user from outside the conversation account (no account_user found)' do
      outsider_account = create(:account)
      outsider = create(:user, account: outsider_account, role: :agent)

      expect { described_class.enforce_send!(outsider, conversation, template_params) }
        .to raise_error(Peakwine::TemplateAccess::Denied)
    end

    it 'denies an unpermitted ActionController::Parameters payload (audit B1 — the main send path)' do
      raw_params = ActionController::Parameters.new(
        content: 'forced',
        template_params: { name: template_name, language: 'id', namespace: 'ns' }
      )

      expect { described_class.enforce_send!(assigned_agent, conversation, raw_params[:template_params]) }
        .to raise_error(Peakwine::TemplateAccess::Denied, I18n.t('errors.whatsapp_template_access_denied'))
    end
  end

  describe '.template_name_from' do
    it 'extracts the name from a string-keyed hash' do
      expect(described_class.template_name_from({ 'name' => 'x', 'language' => 'id' })).to eq('x')
    end

    it 'extracts the name from a symbol-keyed hash' do
      expect(described_class.template_name_from({ name: 'x' })).to eq('x')
    end

    it 'extracts the name from an UNPERMITTED ActionController::Parameters (B1 catcher)' do
      raw_params = ActionController::Parameters.new(
        message: { content: 'x', template_params: { name: 'x', language: 'id' } }
      )
      nested = raw_params.dig(:message, :template_params)

      # why bracket access is mandatory: to_h RAISES on unpermitted params (F14)
      expect { nested.to_h }.to raise_error(ActionController::UnfilteredParameters)

      expect(described_class.template_name_from(nested)).to eq('x')
    end

    it 'extracts the name from an unpermitted top-level Parameters value' do
      raw_params = ActionController::Parameters.new(template_params: { 'name' => 'x' })

      expect(described_class.template_name_from(raw_params[:template_params])).to eq('x')
    end

    it 'returns nil for blank and nameless payloads' do
      expect(described_class.template_name_from(nil)).to be_nil
      expect(described_class.template_name_from({})).to be_nil
      expect(described_class.template_name_from({ language: 'id' })).to be_nil
      expect(described_class.template_name_from(ActionController::Parameters.new)).to be_nil
    end
  end
end
