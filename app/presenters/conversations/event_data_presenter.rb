class Conversations::EventDataPresenter < SimpleDelegator
  def push_data(masked: true)
    {
      additional_attributes: additional_attributes,
      can_reply: can_reply?,
      channel: inbox.try(:channel_type),
      contact_inbox: masked_contact_inbox(masked),
      id: display_id,
      inbox_id: inbox_id,
      messages: push_messages,
      labels: label_list,
      meta: push_meta(masked),
      status: status,
      custom_attributes: custom_attributes,
      snoozed_until: snoozed_until,
      unread_count: unread_incoming_messages.count,
      first_reply_created_at: first_reply_created_at,
      priority: priority,
      waiting_since: waiting_since.to_i,
      **push_timestamps
    }
  end

  # Like #push_data but with message text normalized for external integrations (webhooks).
  def webhook_data
    push_data(masked: false).merge(
      account: account.webhook_data,
      messages: webhook_push_messages
    )
  end

  private

  def masked_contact_inbox(masked)
    return contact_inbox if contact_inbox.blank? || !masked || !Masking::ContactMasker.restricted?(Current.account_user)

    # A plain hash (never the record itself) so ActiveJob's GlobalID round-trip
    # cannot reload and rebroadcast the raw source_id.
    {
      id: contact_inbox.id,
      inbox_id: contact_inbox.inbox_id,
      contact_id: contact_inbox.contact_id,
      source_id: Masking::ContactMasker.mask_source_id(contact_inbox.source_id)
    }
  end

  def push_messages
    [messages.where(account_id: account_id).chat.last&.push_event_data].compact
  end

  def webhook_push_messages
    [messages.where(account_id: account_id).chat.last&.webhook_push_event_data].compact
  end

  def push_meta(masked)
    {
      sender: contact.push_event_data(masked: masked),
      assignee: assigned_entity&.push_event_data,
      assignee_type: assignee_type,
      team: team&.push_event_data,
      hmac_verified: contact_inbox&.hmac_verified
    }
  end

  def push_timestamps
    {
      agent_last_seen_at: agent_last_seen_at.to_i,
      contact_last_seen_at: contact_last_seen_at.to_i,
      last_activity_at: last_activity_at.to_i,
      timestamp: last_activity_at.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_f
    }
  end
end
Conversations::EventDataPresenter.prepend_mod_with('Conversations::EventDataPresenter')
