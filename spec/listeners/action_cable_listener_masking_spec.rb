require 'rails_helper'

RSpec.describe ActionCableListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:contact) do
    create(:contact, :with_email, account: account, name: '+6281234567890',
                                  phone_number: '+6281234567890', email: 'peakwine@gmail.com')
  end
  let(:inbox) do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    channel.inbox
  end
  let!(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let!(:message) { create(:message, conversation: conversation, account: account, sender: contact) }
  let(:broadcasts) { [] }

  # The sync dispatcher runs the listener inside the request thread, so the
  # acting administrator's viewer context is live while payloads are built.
  before do
    create(:inbox_member, user: administrator, inbox: inbox)
    allow(ActionCableBroadcastJob).to receive(:perform_later) { |*args| broadcasts << args }
    Current.user = administrator
    Current.account_user = account.account_users.find_by(user_id: administrator.id)
  end

  after { Current.reset }

  def dispatch_conversation_created
    broadcasts.clear
    listener.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conversation, account: account))
  end

  def agent_broadcast
    broadcasts.find { |tokens, _event, _payload| tokens.include?(administrator.pubsub_token) }
  end

  def contact_broadcast
    broadcasts.find { |tokens, _event, _payload| tokens.include?(conversation.contact_inbox.pubsub_token) }
  end

  it 'broadcasts a masked payload to agent tokens even when an administrator is acting' do
    dispatch_conversation_created

    sender = agent_broadcast[2][:meta][:sender]
    expect(sender[:phone_number]).to eq('+62812*****')
    expect(sender[:email]).to eq('pe***@gmail.com')
    expect(sender[:name]).to eq('+62812*****')

    # The viewer context is restored for the request thread afterwards.
    expect(Current.account_user&.role).to eq('administrator')
  end

  it 'broadcasts a raw payload to the contact inbox token' do
    dispatch_conversation_created

    sender = contact_broadcast[2][:meta][:sender]
    expect(sender[:phone_number]).to eq(contact.phone_number)
    expect(sender[:email]).to eq(contact.email)
    expect(sender[:name]).to eq(contact.name)
  end

  it 'sends a plain hash contact_inbox with the masked source_id to agent tokens' do
    dispatch_conversation_created

    contact_inbox = agent_broadcast[2][:contact_inbox]
    expect(contact_inbox).to eq(
      id: conversation.contact_inbox.id,
      inbox_id: conversation.contact_inbox.inbox_id,
      contact_id: conversation.contact_inbox.contact_id,
      source_id: Masking::ContactMasker.mask_source_id(conversation.contact_inbox.source_id)
    )
  end

  it 'sends the raw record contact_inbox to the contact inbox token' do
    dispatch_conversation_created

    expect(contact_broadcast[2][:contact_inbox]).to eq(conversation.contact_inbox)
  end

  it 'masks message broadcasts to agent tokens while the contact token stays raw' do
    broadcasts.clear
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: message))

    expect(agent_broadcast[2][:sender][:phone_number]).to eq('+62812*****')
    expect(contact_broadcast[2][:sender][:phone_number]).to eq(contact.phone_number)
  end
end
