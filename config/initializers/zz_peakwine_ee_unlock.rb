# frozen_string_literal: true

# peakwine: self-healing Enterprise unlock — the only bake point (baked into the
# custom image, never mounted from the host). Both callbacks are no-ops outside
# production or while PEAKWINE_EE_UNLOCK=false; see Peakwine::EeUnlock.active?.

Rails.application.config.after_initialize do
  Peakwine::EeUnlock.run_after_initialize!
end

# to_prepare (not after_initialize) because the job class autoloads/reloads.
# zz_* runs after 01_inject_enterprise_edition_module.rb, so this prepend lands
# in front of the EE overlay and our perform wins.
Rails.application.reloader.to_prepare do
  Peakwine::EeUnlock.run_to_prepare!
end
