# frozen_string_literal: true

# peakwine: self-healing Enterprise unlock.
# Enforces the plan config and every premium feature flag on each boot so any
# reset (hub sync job, refresh button, manual edit, new image pull) is healed at
# the next restart. Kill-switch: PEAKWINE_EE_UNLOCK=false (env) + restart.
module Peakwine::EeUnlock
  PLAN = 'enterprise'
  PLAN_CONFIG_NAME = 'INSTALLATION_PRICING_PLAN'
  QUANTITY_CONFIG_NAME = 'INSTALLATION_PRICING_PLAN_QUANTITY'
  QUANTITY_FLOOR = 100
  # ALL premium flags (config/features.yml, 18 entries) — without exception.
  # channel_voice per user decision 2026-08-23: the flag being ON does not make
  # Chatwoot receive calls by itself — real calls still depend on the WABA /
  # telephony channel configuration in the provider dashboard.
  FLAGS = %i[
    advanced_assignment advanced_search advanced_search_indexing audit_logs
    captain_document_auto_sync captain_integration captain_integration_v2
    captain_v1_action_classifier channel_voice companies
    conversation_required_attributes csat_review_notes custom_roles
    custom_tools disable_branding help_center_embedding_search saml sla
  ].freeze
  # Fill after branding is re-entered in super admin (follow-up commit).
  # Key = InstallationConfig name, value = value to restore. Empty = skip.
  BRAND_SNAPSHOT = {}.freeze

  LOCK = Mutex.new

  # Prepended onto Internal::CheckNewVersionsJob (above the EE overlay) so every
  # perform path — cron, /super_admin/settings refresh button, manual enqueue —
  # stops here: no hub ping, no plan write, no reconcile.
  HUB_JOB_NO_OP = Module.new do
    def perform
      Rails.logger.info('peakwine ee_unlock: Internal::CheckNewVersionsJob skipped (hub plan sync disabled)')
    end
  end

  module_function

  def enabled?
    ENV.fetch('PEAKWINE_EE_UNLOCK', 'true').downcase != 'false'
  end

  # Heals plan/quantity/flags/branding. Returns true when something was written,
  # false when nothing changed or on error — boot must never fail because of the
  # unlock, errors are logged and swallowed.
  def apply!
    changed = false

    LOCK.synchronize do
      changed = enforce_plan_config
      changed |= enforce_account_flags
      changed |= enforce_branding_snapshot
    end

    GlobalConfig.clear_cache if changed
    Rails.logger.info("peakwine ee_unlock: applied=#{changed} plan=#{PLAN} flags=#{FLAGS.size}")
    changed
  rescue StandardError => e
    Rails.logger.error("peakwine ee_unlock: apply! failed (#{e.class}: #{e.message}); boot continues")
    false
  end

  def enforce_plan_config
    wrote = false
    plan = InstallationConfig.find_or_initialize_by(name: PLAN_CONFIG_NAME)
    if plan.value != PLAN
      plan.value = PLAN
      plan.save!
      wrote = true
    end

    quantity = InstallationConfig.find_or_initialize_by(name: QUANTITY_CONFIG_NAME)
    if quantity.value.to_i < QUANTITY_FLOOR
      quantity.value = QUANTITY_FLOOR
      quantity.save!
      wrote = true
    end

    wrote
  end

  def enforce_account_flags
    wrote = false
    Account.find_each do |account|
      missing = FLAGS - account.enabled_features.keys.map(&:to_sym)
      next if missing.empty?

      account.enable_features!(*missing)
      wrote = true
    end
    wrote
  end

  def enforce_branding_snapshot
    wrote = false
    BRAND_SNAPSHOT.each do |name, value|
      config = InstallationConfig.find_or_initialize_by(name: name.to_s)
      next unless config.value != value || config.locked?

      config.value = value
      config.locked = false
      config.save!
      wrote = true
    end
    wrote
  end
end
