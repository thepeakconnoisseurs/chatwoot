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
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    agent_tokens = user_tokens(account, conversation.inbox.members)
    contact_tokens = contact_tokens(conversation.contact_inbox, message)

    broadcast_masked(account, agent_tokens, MESSAGE_CREATED) { message.push_event_data }
    broadcast(account, contact_tokens, MESSAGE_CREATED, message.push_event_data(masked: false))
  end

  def message_updated(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    agent_tokens = user_tokens(account, conversation.inbox.members)
    contact_tokens = contact_tokens(conversation.contact_inbox, message)

    broadcast_masked(account, agent_tokens, MESSAGE_UPDATED) { message.push_event_data.merge(previous_changes: event.data[:previous_changes]) }
    broadcast(account, contact_tokens, MESSAGE_UPDATED,
              message.push_event_data(masked: false).merge(previous_changes: event.data[:previous_changes]))
  end

  def first_reply_created(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_masked(account, tokens, FIRST_REPLY_CREATED) { message.push_event_data }
  end

  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    agent_tokens = user_tokens(account, conversation.inbox.members)
    contact_tokens = contact_inbox_tokens(conversation.contact_inbox)

    broadcast_masked(account, agent_tokens, CONVERSATION_CREATED) { conversation.push_event_data }
    broadcast(account, contact_tokens, CONVERSATION_CREATED, conversation.push_event_data(masked: false))
  end

  def conversation_read(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_masked(account, tokens, CONVERSATION_READ) { conversation.push_event_data }
  end

  def conversation_status_changed(event)
    conversation, account = extract_conversation_and_account(event)
    agent_tokens = user_tokens(account, conversation.inbox.members)
    contact_tokens = contact_inbox_tokens(conversation.contact_inbox)

    broadcast_masked(account, agent_tokens, CONVERSATION_STATUS_CHANGED) { conversation.push_event_data }
    broadcast(account, contact_tokens, CONVERSATION_STATUS_CHANGED, conversation.push_event_data(masked: false))
  end

  def conversation_updated(event)
    conversation, account = extract_conversation_and_account(event)
    agent_tokens = user_tokens(account, conversation.inbox.members)
    contact_tokens = contact_inbox_tokens(conversation.contact_inbox)

    broadcast_masked(account, agent_tokens, CONVERSATION_UPDATED) { conversation.push_event_data }
    broadcast(account, contact_tokens, CONVERSATION_UPDATED, conversation.push_event_data(masked: false))
  end

  def conversation_unread_count_changed(event)
    account, inbox_members = ::Conversations::UnreadCounts::BroadcastScope.new(event).perform
    return if account.blank? || !account.feature_enabled?('conversation_unread_counts')

    tokens = user_tokens(account, inbox_members)

    broadcast(account, tokens, CONVERSATION_UNREAD_COUNT_CHANGED, {})
  end

  def conversation_typing_on(event)
    conversation = event.data[:conversation]
    account = conversation.account
    user = event.data[:user]
    agent_tokens = typing_agent_tokens(account, conversation, user)
    contact_tokens = typing_contact_tokens(conversation, user)

    broadcast_masked(account, agent_tokens, CONVERSATION_TYPING_ON) { typing_payload(event, conversation, user, masked: true) }
    broadcast(account, contact_tokens, CONVERSATION_TYPING_ON, typing_payload(event, conversation, user, masked: false))
  end

  def conversation_typing_off(event)
    conversation = event.data[:conversation]
    account = conversation.account
    user = event.data[:user]
    agent_tokens = typing_agent_tokens(account, conversation, user)
    contact_tokens = typing_contact_tokens(conversation, user)

    broadcast_masked(account, agent_tokens, CONVERSATION_TYPING_OFF) { typing_payload(event, conversation, user, masked: true) }
    broadcast(account, contact_tokens, CONVERSATION_TYPING_OFF, typing_payload(event, conversation, user, masked: false))
  end

  def assignee_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_masked(account, tokens, ASSIGNEE_CHANGED) { conversation.push_event_data }
  end

  def team_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_masked(account, tokens, TEAM_CHANGED) { conversation.push_event_data }
  end

  def conversation_contact_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast_masked(account, tokens, CONVERSATION_CONTACT_CHANGED) { conversation.push_event_data }
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

  def account_token(account)
    "account_#{account.id}"
  end

  # Agent-side tokens for typing events: the pubsub token of the typing user
  # (when it is an agent) is excluded so the typer does not get their own echo.
  def typing_agent_tokens(account, conversation, user)
    tokens = user_tokens(account, conversation.inbox.members)
    return tokens unless user.respond_to?(:pubsub_token) && !user.is_a?(Contact)

    tokens - [user.pubsub_token]
  end

  # Contact-side tokens for typing events: the contact inbox session only
  # receives the echo when an agent is typing, never the contact itself.
  def typing_contact_tokens(conversation, user)
    return [] if user.is_a?(Contact)

    [conversation.contact_inbox.pubsub_token]
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

  def user_tokens(account, agents)
    agent_tokens = agents.pluck(:pubsub_token)
    admin_tokens = account.administrators.pluck(:pubsub_token)
    (agent_tokens + admin_tokens).uniq
  end

  def contact_tokens(contact_inbox, message)
    return [] if message.private?
    return [] if message.activity?
    return [] if contact_inbox.nil?

    contact_inbox_tokens(contact_inbox)
  end

  def contact_inbox_tokens(contact_inbox)
    contact = contact_inbox.contact

    contact_inbox.hmac_verified? ? contact.contact_inboxes.where(hmac_verified: true).filter_map(&:pubsub_token) : [contact_inbox.pubsub_token]
  end

  def broadcast(account, tokens, event_name, data)
    return if tokens.blank?

    payload = data.merge(account_id: account.id)
    # So the frondend knows who performed the action.
    # Useful in cases like conversation assignment for generating a notification with assigner name.
    payload[:performer] = Current.user&.push_event_data if Current.user.present?

    ::ActionCableBroadcastJob.perform_later(tokens.uniq, event_name, payload)
  end

  # Builds the broadcast payload without any viewer context. The sync dispatcher
  # runs this listener inside the request thread, so the acting user's
  # Current.account_user would otherwise leak raw contact data to every
  # subscriber of the agent-facing tokens.
  def broadcast_masked(account, tokens, event_name, &)
    return if tokens.blank?

    broadcast(account, tokens, event_name, with_no_viewer_context(&))
  end

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
