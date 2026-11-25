require 'rails_helper'

RSpec.describe ActionCableListener do
  # The sync dispatcher runs the listener inside the request thread, so the
  # acting user's viewer context is live while payloads are built. Whoever the
  # actor is, agent tokens get the no-viewer (masked) payload and contact/client
  # sessions the raw one; web widget sessions get the widget payload.
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:typing_agent) { create(:user, account: account, role: :agent) }
  let(:contact) do
    create(:contact, :with_email, account: account, name: '+6281234567890',
                                  phone_number: '+6281234567890', email: 'peakwine@gmail.com')
  end
  # A WhatsApp inbox is not a web widget: the contact session sits on the client
  # side of the upstream split and receives the raw payload as a job member.
  let(:inbox) do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    channel.inbox
  end
  let!(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let!(:message) { create(:message, conversation: conversation, account: account, sender: contact) }
  let(:broadcasts) { [] }
  let(:contact_token) { conversation.contact_inbox.pubsub_token }
  let(:masked_phone) { '+62812*****' }
  let(:masked_email) { 'pe***@gmail.com' }
  let(:masked_source_id) { Masking::ContactMasker.mask_source_id(conversation.contact_inbox.source_id) }

  before do
    create(:inbox_member, user: administrator, inbox: inbox)
    allow(ActionCableBroadcastJob).to receive(:perform_later) { |*args, **kwargs| broadcasts << [args, kwargs] }
  end

  after { Current.reset }

  def dispatch(event_name, data)
    broadcasts.clear
    listener.public_send(event_name.to_s.tr('.', '_'), Events::Base.new(event_name, Time.zone.now, **data))
  end

  def tokens_of(broadcast)
    broadcast[0][0]
  end

  def payload_of(broadcast)
    broadcast[0][2]
  end

  def widget_data_of(broadcast)
    broadcast[1][:widget_data]
  end

  def agent_broadcast
    broadcasts.find { |broadcast| tokens_of(broadcast).include?(administrator.pubsub_token) }
  end

  def contact_broadcast
    broadcasts.find { |broadcast| tokens_of(broadcast).include?(contact_token) }
  end

  shared_examples 'a split audience' do
    it 'sends message.created masked to agent tokens and raw to the contact token' do
      dispatch(:'message.created', message: message)

      expect(tokens_of(agent_broadcast)).not_to include(contact_token)
      expect(tokens_of(contact_broadcast)).to eq([contact_token])
      expect(payload_of(agent_broadcast)[:sender]).to include(phone_number: masked_phone, email: masked_email, name: masked_phone)
      expect(payload_of(agent_broadcast)[:conversation][:contact_inbox][:source_id]).to eq(masked_source_id)
      expect(payload_of(contact_broadcast)[:sender]).to include(phone_number: contact.phone_number, email: contact.email, name: contact.name)
      expect(payload_of(contact_broadcast)[:conversation][:contact_inbox][:source_id]).to eq(conversation.contact_inbox.source_id)
    end

    it 'sends message.updated masked to agent tokens and raw to the contact token, both with the extra data' do
      dispatch(:'message.updated', message: message, previous_changes: { 'status' => %w[sent delivered] })

      expect(payload_of(agent_broadcast)[:previous_changes]).to eq('status' => %w[sent delivered])
      expect(payload_of(agent_broadcast)[:sender][:phone_number]).to eq(masked_phone)
      expect(payload_of(contact_broadcast)[:previous_changes]).to eq('status' => %w[sent delivered])
      expect(payload_of(contact_broadcast)[:sender][:phone_number]).to eq(contact.phone_number)
    end

    it 'sends conversation.created masked to agent tokens and raw to the contact token' do
      dispatch(:'conversation.created', conversation: conversation, account: account)

      expect(payload_of(agent_broadcast)[:meta][:sender]).to include(phone_number: masked_phone, email: masked_email, name: masked_phone)
      expect(payload_of(contact_broadcast)[:meta][:sender]).to include(phone_number: contact.phone_number, email: contact.email, name: contact.name)
    end

    it 'sends conversation.status_changed masked to agent tokens and raw to the contact token' do
      dispatch(:'conversation.status_changed', conversation: conversation)

      expect(payload_of(agent_broadcast)[:meta][:sender][:phone_number]).to eq(masked_phone)
      expect(payload_of(contact_broadcast)[:meta][:sender][:phone_number]).to eq(contact.phone_number)
    end

    it 'sends the typing event masked to the other agents and raw to the contact token' do
      dispatch(:'conversation.typing_on', conversation: conversation, user: typing_agent, is_private: false)

      expect(tokens_of(agent_broadcast)).to eq([administrator.pubsub_token])
      expect(payload_of(agent_broadcast)[:conversation][:meta][:sender][:phone_number]).to eq(masked_phone)
      expect(payload_of(agent_broadcast)[:user]).to eq(typing_agent.push_event_data)
      expect(tokens_of(contact_broadcast)).to eq([contact_token])
      expect(payload_of(contact_broadcast)[:conversation][:meta][:sender][:phone_number]).to eq(contact.phone_number)
    end

    it 'restores the viewer context of the calling thread afterwards' do
      acting_account_user = Current.account_user

      dispatch(:'message.created', message: message)
      dispatch(:'conversation.created', conversation: conversation, account: account)
      dispatch(:'conversation.typing_off', conversation: conversation, user: typing_agent, is_private: false)

      expect(Current.account_user).to equal(acting_account_user)
    end
  end

  context 'when an administrator is acting' do
    before do
      Current.user = administrator
      Current.account_user = administrator.account_users.find_by(account_id: account.id)
    end

    it_behaves_like 'a split audience'

    it 'broadcasts a masked payload to agent tokens even though the administrator may view raw contact data' do
      dispatch(:'conversation.created', conversation: conversation, account: account)

      sender = payload_of(agent_broadcast)[:meta][:sender]
      expect(sender[:phone_number]).to eq(masked_phone)
      expect(sender[:email]).to eq(masked_email)
      expect(sender[:name]).to eq(masked_phone)
      expect(Current.account_user&.role).to eq('administrator')
    end

    it 'sends a plain hash contact_inbox with the masked source_id to agent tokens' do
      dispatch(:'conversation.created', conversation: conversation, account: account)

      expect(payload_of(agent_broadcast)[:contact_inbox]).to eq(
        id: conversation.contact_inbox.id,
        inbox_id: conversation.contact_inbox.inbox_id,
        contact_id: conversation.contact_inbox.contact_id,
        source_id: masked_source_id
      )
    end

    it 'sends the raw record contact_inbox to the contact inbox token' do
      dispatch(:'conversation.created', conversation: conversation, account: account)

      expect(payload_of(contact_broadcast)[:contact_inbox]).to eq(conversation.contact_inbox)
    end

    it 'carries the event data in both jobs of the split' do
      dispatch(:'conversation.created', conversation: conversation, account: account)

      expect(broadcasts.size).to eq(2)
      expect(broadcasts.map { |broadcast| broadcast[0][1] }).to all(eq('conversation.created'))
      expect(payload_of(agent_broadcast)[:id]).to eq(conversation.display_id)
      expect(payload_of(contact_broadcast)[:id]).to eq(conversation.display_id)
    end
  end

  context 'when there is no viewer context (job context)' do
    before { Current.reset }

    it_behaves_like 'a split audience'
  end

  context 'when a custom-role agent without contact_manage is acting' do
    let(:restricted_agent) { create(:user, account: account, role: :agent) }

    before do
      custom_role = create(:custom_role, account: account, permissions: %w[conversation_manage])
      restricted_agent.account_users.find_by(account_id: account.id).update!(custom_role: custom_role)
      Current.user = restricted_agent
      Current.account_user = restricted_agent.account_users.find_by(account_id: account.id)
    end

    it_behaves_like 'a split audience'
  end

  context 'with a web widget session' do
    let(:inbox) { create(:inbox, account: account) }

    before do
      Current.user = administrator
      Current.account_user = administrator.account_users.find_by(account_id: account.id)
    end

    def widget_broadcast
      broadcasts.find { |broadcast| broadcast[1][:widget_members].present? }
    end

    it 'sends agent tokens the masked message and the widget session the widget payload' do
      dispatch(:'message.created', message: message)

      expect(payload_of(agent_broadcast)[:sender][:phone_number]).to eq(masked_phone)
      expect(tokens_of(agent_broadcast)).not_to include(contact_token)

      expect(tokens_of(widget_broadcast)).to eq([])
      expect(widget_broadcast[1][:widget_members]).to eq([contact_token])
      expect(widget_data_of(widget_broadcast)[:sender]).to eq(type: 'contact')
      expect(widget_data_of(widget_broadcast)[:content]).to eq(message.content)
      expect(widget_data_of(widget_broadcast)[:account_id]).to eq(account.id)
    end

    it 'sends the widget session only the widget payload of a conversation event' do
      dispatch(:'conversation.status_changed', conversation: conversation)

      widget_data = widget_data_of(widget_broadcast)
      expect(widget_data).to include(conversation.widget_push_event_data)
      expect(widget_data[:account_id]).to eq(account.id)
      expect(widget_data.keys).not_to include(:meta, :contact_inbox)
    end

    it 'does not message the widget session on conversation.updated, which has no handler for it' do
      dispatch(:'conversation.updated', conversation: conversation)

      expect(broadcasts.size).to eq(1)
      expect(broadcasts[0][1]).to eq({})
    end
  end

  context 'with a Client API session' do
    let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }

    before do
      Current.user = administrator
      Current.account_user = administrator.account_users.find_by(account_id: account.id)
    end

    it 'sends the client session the raw message as a job member, outside the agents job' do
      dispatch(:'message.created', message: message)

      expect(tokens_of(agent_broadcast)).to eq([administrator.pubsub_token])
      expect(payload_of(agent_broadcast)[:sender][:phone_number]).to eq(masked_phone)
      expect(contact_broadcast[1]).to eq({})
      expect(tokens_of(contact_broadcast)).to eq([contact_token])
      expect(payload_of(contact_broadcast)[:sender][:phone_number]).to eq(contact.phone_number)
    end
  end
end
