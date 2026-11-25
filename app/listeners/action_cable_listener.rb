# rubocop:disable Metrics/ClassLength
class ActionCableListener < BaseListener
  include Events::Types

  def notification_created(event)
    notification, account, unread_count, count = extract_notification_and_account(event)
    tokens = [event.data[:notification].user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_CREATED, { notification: notification.push_event_data, unread_count: unread_count, count: count })
  end

  def notification_updated(event)
    notification, account, unread_count, count = extract_notification_and_account(event)
    tokens = [event.data[:notification].user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_UPDATED, { notification: notification.push_event_data, unread_count: unread_count, count: count })
  end

  def notification_deleted(event)
    notification_data = event.data[:notification_data]

    user = User.find_by(id: notification_data[:user_id])
    account = Account.find_by(id: notification_data[:account_id])
    return if user.blank? || account.blank?

    notification_finder = NotificationFinder.new(user, account)
    tokens = [user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_DELETED, {
                notification: { id: notification_data[:id] },
                unread_count: notification_finder.unread_count,
                count: notification_finder.count
              })
  end

  def account_cache_invalidated(event)
    account = event.data[:account]
    tokens = user_tokens(account, account.agents)

    broadcast(account, tokens, ACCOUNT_CACHE_INVALIDATED, {
                cache_keys: event.data[:cache_keys]
              })
  end

  def message_created(event)
    broadcast_message_event(event.data[:message], MESSAGE_CREATED)
  end

  def message_updated(event)
    broadcast_message_event(event.data[:message], MESSAGE_UPDATED, previous_changes: event.data[:previous_changes])
  end

  def first_reply_created(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_masked(account, tokens, FIRST_REPLY_CREATED) { message.push_event_data }
  end

  def conversation_created(event)
    broadcast_conversation_event(event.data[:conversation], CONVERSATION_CREATED)
  end

  def conversation_bot_handoff(event)
    broadcast_to_inbox_members(event, CONVERSATION_BOT_HANDOFF)
  end

  def conversation_read(event)
    broadcast_to_inbox_members(event, CONVERSATION_READ)
  end

  def conversation_status_changed(event)
    broadcast_conversation_event(event.data[:conversation], CONVERSATION_STATUS_CHANGED)
  end

  def conversation_updated(event)
    broadcast_conversation_event(event.data[:conversation], CONVERSATION_UPDATED)
  end

  def conversation_unread_count_changed(event)
    account, inbox_members = ::Conversations::UnreadCounts::BroadcastScope.new(event).perform
    return if account.blank? || !account.feature_enabled?('conversation_unread_counts')

    tokens = user_tokens(account, inbox_members)

    broadcast(account, tokens, CONVERSATION_UNREAD_COUNT_CHANGED, {})
  end

  def conversation_typing_on(event)
    broadcast_typing_event(event, CONVERSATION_TYPING_ON)
  end

  def conversation_typing_off(event)
    broadcast_typing_event(event, CONVERSATION_TYPING_OFF)
  end

  def assignee_changed(event)
    # Model callbacks identify automatic assignment (auto-assignment or automation
    # rules) by performed_by. The V2 AssignmentService also dispatches an event with
    # user (the assigned agent, NOT the performer). Neither requires inferring
    # automation from a missing Current.user.
    automatic_assignment = [Inbox, AssignmentPolicy, AutomationRule].include?(event.data[:performed_by].class) || event.data[:user].present?
    broadcast_to_inbox_members(event, ASSIGNEE_CHANGED, automatic_assignment: automatic_assignment)
  end

  def team_changed(event)
    broadcast_to_inbox_members(event, TEAM_CHANGED)
  end

  def conversation_contact_changed(event)
    broadcast_to_inbox_members(event, CONVERSATION_CONTACT_CHANGED)
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)
    broadcast_masked(account, [account_token(account)], CONTACT_CREATED) { contact.push_event_data }
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    broadcast_masked(account, [account_token(account)], CONTACT_UPDATED) { contact.push_event_data }
  end

  def contact_merged(event)
    contact, account = extract_contact_and_account(event)
    broadcast_masked(account, [account_token(account)], CONTACT_MERGED) { contact.push_event_data }
  end

  def contact_deleted(event)
    contact_data = event.data[:contact_data]
    account = Account.find_by(id: contact_data[:account_id])
    return if account.blank?

    broadcast(account, [account_token(account)], CONTACT_DELETED, masked_contact_data(contact_data))
  end

  def conversation_mentioned(event)
    conversation, account = extract_conversation_and_account(event)
    user = event.data[:user]

    broadcast_masked(account, [user.pubsub_token], CONVERSATION_MENTIONED) { conversation.push_event_data }
  end

  private

  # Upstream helper: broadcast to inbox members + optional metadata.
  # Peakwine: the payload is built without any viewer context (see with_no_viewer_context).
  def broadcast_to_inbox_members(event, event_name, **metadata)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)
    return if tokens.blank?

    payload = with_no_viewer_context { conversation.push_event_data }
    broadcast(account, tokens, event_name, payload.merge(metadata))
  end

  def account_token(account)
    "account_#{account.id}"
  end

  # Peakwine: the sync dispatcher runs this listener inside the request thread, so the
  # acting user's viewer context is live while payloads are built. Each helper therefore
  # broadcasts twice: agents get the payload built without a viewer (masked for every
  # role), and contact/client sessions get the raw payload (`masked: false`) together
  # with the widget payload in the second broadcast.
  def broadcast_message_event(message, event_name, **extra)
    conversation = message.conversation
    widget_tokens, client_tokens = split_contact_tokens(message_contact_inboxes(conversation, message))
    data = with_no_viewer_context { message.push_event_data.merge(extra) }
    broadcast(conversation.account, inbox_user_tokens(conversation), event_name, data)
    return if client_tokens.blank? && widget_tokens.blank?

    contact_data = message.push_event_data(masked: false).merge(extra)
    broadcast(conversation.account, client_tokens, event_name, contact_data,
              widget: { tokens: widget_tokens, data: message.widget_push_event_data(contact_data) })
  end

  def broadcast_conversation_event(conversation, event_name)
    widget_tokens, client_tokens = split_contact_tokens(session_contact_inboxes(conversation.contact_inbox))
    # The web widget has no handler for conversation.updated
    widget_tokens = [] if event_name == CONVERSATION_UPDATED

    broadcast(conversation.account, inbox_user_tokens(conversation), event_name, with_no_viewer_context { conversation.push_event_data })
    return if client_tokens.blank? && widget_tokens.blank?

    contact_data = conversation.push_event_data(masked: false)
    broadcast(conversation.account, client_tokens, event_name, contact_data,
              widget: { tokens: widget_tokens, data: conversation.widget_push_event_data })
  end

  def broadcast_typing_event(event, event_name)
    conversation = event.data[:conversation]
    user = event.data[:user]
    widget_tokens, client_tokens = split_contact_tokens(typing_contact_inboxes(conversation, user))
    data = with_no_viewer_context { typing_payload(event, conversation, user, masked: true) }

    broadcast(conversation.account, typing_user_tokens(conversation, user), event_name, data)
    return if client_tokens.blank? && widget_tokens.blank?

    contact_data = typing_payload(event, conversation, user, masked: false)
    broadcast(conversation.account, client_tokens, event_name, contact_data,
              widget: { tokens: widget_tokens, data: contact_data.merge(conversation: conversation.widget_push_event_data) })
  end

  # Web widget sessions get the widget payload.
  # Client API sessions get the same full payload as agents and admins.
  def split_contact_tokens(contact_inboxes)
    widget_inboxes, client_inboxes = contact_inboxes.partition { |contact_inbox| contact_inbox.inbox.web_widget? }
    [widget_inboxes.filter_map(&:pubsub_token), client_inboxes.filter_map(&:pubsub_token)]
  end

  def inbox_user_tokens(conversation)
    user_tokens(conversation.account, conversation.inbox.members)
  end

  # Whoever is typing does not get their own typing event
  def typing_user_tokens(conversation, user)
    tokens = inbox_user_tokens(conversation)
    user.respond_to?(:pubsub_token) ? tokens - [user.pubsub_token] : tokens
  end

  def typing_contact_inboxes(conversation, user)
    user.is_a?(Contact) ? [] : [conversation.contact_inbox]
  end

  def user_tokens(account, agents)
    agent_tokens = agents.pluck(:pubsub_token)
    admin_tokens = account.administrators.pluck(:pubsub_token)
    (agent_tokens + admin_tokens).uniq
  end

  def message_contact_inboxes(conversation, message)
    return [] if message.private? || message.activity? || conversation.contact_inbox.nil?

    session_contact_inboxes(conversation.contact_inbox)
  end

  # A verified session also reaches the contact's other verified sessions, in any inbox that still exists
  def session_contact_inboxes(contact_inbox)
    return [contact_inbox] unless contact_inbox.hmac_verified?

    contact_inbox.contact.contact_inboxes.where(hmac_verified: true).where.associated(:inbox).includes(:inbox).to_a
  end

  # widget: { tokens:, data: } sends web widget sessions their payload in the same job
  def broadcast(account, tokens, event_name, data, widget: {})
    widget_tokens = widget[:tokens].to_a
    return if tokens.blank? && widget_tokens.blank?

    widget_options = {}
    widget_options = { widget_members: widget_tokens.uniq, widget_data: broadcast_payload(account, widget[:data]) } if widget_tokens.present?
    ::ActionCableBroadcastJob.perform_later(tokens.uniq, event_name, broadcast_payload(account, data), **widget_options)
  end

  def broadcast_payload(account, data)
    payload = data.merge(account_id: account.id)
    # So the frondend knows who performed the action.
    # Useful in cases like conversation assignment for generating a notification with assigner name.
    payload[:performer] = Current.user&.push_event_data if Current.user.present?
    payload
  end

  def typing_payload(event, conversation, user, masked:)
    {
      conversation: conversation.push_event_data(masked: masked),
      user: user.is_a?(Contact) ? user.push_event_data(masked: masked) : user.push_event_data,
      is_private: event.data[:is_private] || false
    }
  end

  # The payload sent to contact inbox sessions (widget visitors) must stay raw;
  # everything else is masked via the builders that receive no viewer context.
  def masked_contact_data(contact_data)
    contact_data.merge(
      email: Masking::ContactMasker.mask_email(contact_data[:email]),
      identifier: Masking::ContactMasker.mask_source_id(contact_data[:identifier]),
      name: Masking::ContactMasker.mask_name_if_phone(contact_data[:name]),
      phone_number: Masking::ContactMasker.mask_phone(contact_data[:phone_number])
    )
  end

  def broadcast_masked(account, tokens, event_name, &)
    return if tokens.blank?

    broadcast(account, tokens, event_name, with_no_viewer_context(&))
  end

  # Builds the broadcast payload without any viewer context. The sync dispatcher
  # runs this listener inside the request thread, so the acting user's
  # Current.account_user would otherwise leak raw contact data to every
  # subscriber of the agent-facing tokens.
  def with_no_viewer_context
    previous_account_user = Current.account_user
    Current.account_user = nil
    begin
      yield
    ensure
      Current.account_user = previous_account_user
    end
  end
end

ActionCableListener.prepend_mod_with('ActionCableListener')
# rubocop:enable Metrics/ClassLength
