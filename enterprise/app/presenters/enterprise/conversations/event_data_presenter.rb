module Enterprise::Conversations::EventDataPresenter
  def push_data(masked: true)
    return super(masked: masked) unless account.feature_enabled?('sla')

    sla_applicable = sla_applicable?

    super(masked: masked).merge(
      applied_sla: sla_applicable ? applied_sla&.push_event_data : nil,
      sla_events: sla_applicable ? sla_events.map(&:push_event_data) : [],
      sla_policy_id: sla_applicable ? sla_policy_id : nil
    )
  end
end
