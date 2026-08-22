# frozen_string_literal: true

# peakwine: self-healing Enterprise unlock — enforces plan/quantity/premium
# flags on every boot (any reset heals at the next restart) and clears the
# stale reset-warning banner the no-op'd reconcile job can no longer remove.
# Kill-switch: PEAKWINE_EE_UNLOCK=false (env) + restart.
module Peakwine::EeUnlock
  PLAN = 'enterprise'
  PLAN_CONFIG_NAME = 'INSTALLATION_PRICING_PLAN'
  QUANTITY_CONFIG_NAME = 'INSTALLATION_PRICING_PLAN_QUANTITY'
  QUANTITY_FLOOR = 100
  # ALL premium flags (config/features.yml, 18 entries) — without exception.
  # channel_voice (user 2026-08-23): flag ON alone cannot receive calls; real
  # calls still need WABA/telephony channel config in the provider dashboard.
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

  # Prepended onto Internal::CheckNewVersionsJob (above the EE overlay): every
  # perform path — cron, refresh button, manual enqueue — stops here.
  HUB_JOB_NO_OP = Module.new do
    def perform
      Rails.logger.info('peakwine ee_unlock: Internal::CheckNewVersionsJob skipped (hub plan sync disabled)')
    end
  end

  module_function

  # Shared guard for both boot callbacks: production-only + kill-switch.
  def active?
    Rails.env.production? && enabled?
  end

  def enabled?
    ENV.fetch('PEAKWINE_EE_UNLOCK', 'true').downcase != 'false'
  end

  # Boot callback bodies — the initializer only registers these one-liners.
  def run_after_initialize!
    return unless active?

    apply!
  end

  def run_to_prepare!
    return unless active?

    Internal::CheckNewVersionsJob.prepend(HUB_JOB_NO_OP)
  end

  # Heals plan/quantity/flags/branding. Returns true when something was written,
  # false when nothing changed or on error — boot must never fail because of the
  # unlock, errors are logged and swallowed.
  def apply!
    return false unless database_reachable?

    changed = false

    LOCK.synchronize do
      changed |= run_step(:enforce_plan_config)
      changed |= run_step(:enforce_account_flags)
      changed |= run_step(:enforce_branding_snapshot)
    end

    # the reset-warning banner is normally removed by the reconcile job we
    # neutralized above — clear it on every successful pass, healed or not
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
    GlobalConfig.clear_cache if changed
    Rails.logger.info("peakwine ee_unlock: applied=#{changed} plan=#{PLAN} flags=#{FLAGS.size}")
    changed
  rescue StandardError => e
    Rails.logger.error("peakwine ee_unlock: apply! failed (#{e.class}: #{e.message}); boot continues")
    false
  end

  # Fresh install / assets:precompile boots without a DB — skip quietly instead
  # of flooding the log with error-level noise from the generic rescue.
  def database_reachable?
    ActiveRecord::Base.connection
    true
  rescue StandardError => e
    Rails.logger.info("peakwine ee_unlock: skipped (database unavailable: #{e.class})")
    false
  end

  # One failing step (bad row, unique-index race against a concurrently booting
  # container) must not skip the remaining steps for this boot.
  def run_step(step)
    public_send(step)
  rescue StandardError => e
    Rails.logger.error("peakwine ee_unlock: #{step} failed (#{e.class}: #{e.message}); continuing")
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
    # intersect with Featurable's defined names so an upstream flag rename can
    # never make enable_features! raise for the whole run
    healable = FLAGS & Featurable::FEATURE_LIST.pluck('name').map(&:to_sym)
    Account.find_each do |account|
      missing = healable - account.enabled_features.keys.map(&:to_sym)
      next if missing.empty?

      begin
        persisted = account.enable_features!(*missing)
        persisted ? wrote = true : Rails.logger.error("peakwine ee_unlock: saving flags failed for account #{account.id}")
      rescue StandardError => e
        Rails.logger.error("peakwine ee_unlock: account #{account.id} flags not applied (#{e.class}: #{e.message}); continuing")
      end
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
