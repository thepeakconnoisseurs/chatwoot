require 'rails_helper'

RSpec.describe Peakwine::EeUnlock do
  describe 'FLAGS' do
    it 'equals the premium set of config/features.yml (18 flags incl. channel_voice)' do
      premium = Featurable::FEATURE_LIST.select { |feature| feature['premium'] }.pluck('name').map(&:to_sym)

      expect(premium.size).to eq(18)
      expect(described_class::FLAGS).to match_array(premium)
      expect(described_class::FLAGS).to include(:channel_voice)
    end
  end

  describe '.enabled?' do
    it 'defaults to enabled when the env is unset' do
      with_modified_env PEAKWINE_EE_UNLOCK: nil do
        expect(described_class.enabled?).to be true
      end
    end

    it 'stays enabled for true in any case' do
      with_modified_env PEAKWINE_EE_UNLOCK: 'TrUe' do
        expect(described_class.enabled?).to be true
      end
    end

    it 'disables for false in any case' do
      with_modified_env PEAKWINE_EE_UNLOCK: 'FALSE' do
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe '.active?' do
    it 'is active in production with the kill-switch unset' do
      allow(Rails.env).to receive(:production?).and_return(true)
      with_modified_env PEAKWINE_EE_UNLOCK: nil do
        expect(described_class.active?).to be true
      end
    end

    it 'short-circuits the callbacks when the kill-switch is set' do
      allow(Rails.env).to receive(:production?).and_return(true)
      with_modified_env PEAKWINE_EE_UNLOCK: 'false' do
        expect(described_class.active?).to be false
      end
    end

    it 'short-circuits the callbacks outside production' do
      allow(Rails.env).to receive(:production?).and_return(false)
      with_modified_env PEAKWINE_EE_UNLOCK: nil do
        expect(described_class.active?).to be false
      end
    end
  end

  describe '.run_after_initialize!' do
    it 'applies the unlock when active' do
      allow(described_class).to receive(:active?).and_return(true)
      allow(described_class).to receive(:apply!).and_return(true)

      described_class.run_after_initialize!

      expect(described_class).to have_received(:apply!)
    end

    it 'does nothing when inactive (non-production or kill-switch)' do
      allow(described_class).to receive(:active?).and_return(false)
      allow(described_class).to receive(:apply!)

      described_class.run_after_initialize!

      expect(described_class).not_to have_received(:apply!)
    end
  end

  describe '.run_to_prepare!' do
    it 'prepends the no-op over Internal::CheckNewVersionsJob when active' do
      job_class = Class.new
      stub_const('Internal::CheckNewVersionsJob', job_class)
      allow(described_class).to receive(:active?).and_return(true)

      described_class.run_to_prepare!

      expect(job_class.ancestors).to include(described_class::HUB_JOB_NO_OP)
    end

    it 'leaves the job class untouched when inactive' do
      job_class = Class.new
      stub_const('Internal::CheckNewVersionsJob', job_class)
      allow(described_class).to receive(:active?).and_return(false)

      described_class.run_to_prepare!

      expect(job_class.ancestors).not_to include(described_class::HUB_JOB_NO_OP)
    end
  end

  describe '.apply!' do
    before do
      allow(GlobalConfig).to receive(:clear_cache)
      allow(Redis::Alfred).to receive(:delete)
      # InstallationConfig pings GlobalConfig.clear_cache from after_commit on
      # every save; silence the callback so received counts prove apply!'s own
      # call. raise: false keeps the group green if the callback is renamed.
      InstallationConfig.skip_callback(:commit, :after, :clear_cache, raise: false)
    end

    after do
      # Restore only when the skip actually removed the callback, so a rename
      # upstream (skip silently no-ops) cannot register a duplicate.
      InstallationConfig.set_callback(:commit, :after, :clear_cache) if InstallationConfig.__callbacks[:commit].empty?
    end

    it 'heals a reset state: plan, quantity and missing flags, clearing the cache exactly once' do
      InstallationConfig.create!(name: 'INSTALLATION_PRICING_PLAN', value: 'community')
      InstallationConfig.create!(name: 'INSTALLATION_PRICING_PLAN_QUANTITY', value: 5)
      account = create(:account)
      account.disable_features!(*described_class::FLAGS)

      expect(described_class.apply!).to be true
      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').value).to eq('enterprise')
      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY').value).to eq(100)
      expect(account.reload.enabled_features.keys.map(&:to_sym)).to include(*described_class::FLAGS)
      expect(GlobalConfig).to have_received(:clear_cache).exactly(:once)
      expect(Redis::Alfred).to have_received(:delete).with(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
    end

    it 'covers accounts created after the previous boot' do
      account = create(:account)

      expect(described_class.apply!).to be true
      expect(account.reload.enabled_features.keys.map(&:to_sym)).to include(*described_class::FLAGS)
    end

    it 'is idempotent: a healed state writes nothing and does not clear the cache' do
      InstallationConfig.create!(name: 'INSTALLATION_PRICING_PLAN', value: 'enterprise')
      InstallationConfig.create!(name: 'INSTALLATION_PRICING_PLAN_QUANTITY', value: 500)
      account = create(:account)
      account.enable_features!(*described_class::FLAGS)
      plan = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')
      quantity = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')

      expect(described_class.apply!).to be false
      expect { described_class.apply! }.not_to(change { [plan, quantity, account].map { |record| record.reload.updated_at } })
      expect(GlobalConfig).not_to have_received(:clear_cache)
      # the reset warning is cleared on every successful pass, healed or not
      # (this example runs two no-change passes)
      expect(Redis::Alfred).to have_received(:delete).with(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING).exactly(:twice)
    end

    it 'raises quantity to the floor but keeps higher values' do
      InstallationConfig.create!(name: 'INSTALLATION_PRICING_PLAN_QUANTITY', value: 500)

      described_class.apply!

      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY').value).to eq(500)
    end

    it 'ignores flag names Featurable no longer defines' do
      stub_const('Peakwine::EeUnlock::FLAGS', %i[sla deleted_upstream_flag])
      account = create(:account)

      expect { described_class.apply! }.not_to raise_error
      expect(account.reload.enabled_features.keys.map(&:to_sym)).to include(:sla)
    end

    it 'continues past a failing account and only counts persisted writes' do
      raising = instance_double(Account, id: 101, enabled_features: {})
      allow(raising).to receive(:enable_features!).and_raise(NoMethodError, 'feature_deleted_flag=')
      unsaved = instance_double(Account, id: 102, enabled_features: {})
      allow(unsaved).to receive(:enable_features!).and_return(false)
      healthy = create(:account)
      allow(Account).to receive(:find_each).and_yield(raising).and_yield(unsaved).and_yield(healthy)
      allow(Rails.logger).to receive(:error)

      expect(described_class.apply!).to be true
      expect(healthy.reload.enabled_features.keys.map(&:to_sym)).to include(*described_class::FLAGS)
      expect(Rails.logger).to have_received(:error).with(/account 101/)
      expect(Rails.logger).to have_received(:error).with(/saving flags failed for account 102/)
    end

    it 'isolates steps: one failing step is logged and does not abort the rest' do
      allow(described_class).to receive(:enforce_plan_config).and_raise(ActiveRecord::RecordNotUnique)
      allow(Rails.logger).to receive(:error)
      account = create(:account)

      expect(described_class.apply!).to be true
      expect(account.reload.enabled_features.keys.map(&:to_sym)).to include(*described_class::FLAGS)
      expect(Rails.logger).to have_received(:error).with(/enforce_plan_config failed/)
    end

    it 'never creates or changes branding InstallationConfigs while BRAND_SNAPSHOT is empty' do
      expect(described_class::BRAND_SNAPSHOT).to be_empty
      branding = InstallationConfig.create!(name: 'INSTALLATION_NAME', value: 'Chatwoot', locked: true)

      described_class.apply!

      expect(branding.reload.value).to eq('Chatwoot')
      expect(branding.reload.locked).to be true
      expect(InstallationConfig.count).to eq(3) # untouched branding row + plan + quantity
    end

    it 'restores branding from a filled snapshot: overwrites drifted values and unlocks locked rows' do
      stub_const('Peakwine::EeUnlock::BRAND_SNAPSHOT', { 'INSTALLATION_NAME' => 'Peakwine', 'BRAND_URL' => 'https://peakwine.id' })
      drifted = InstallationConfig.create!(name: 'INSTALLATION_NAME', value: 'Chatwoot')
      locked_row = InstallationConfig.create!(name: 'BRAND_URL', value: 'https://peakwine.id', locked: true)

      expect(described_class.apply!).to be true
      expect(drifted.reload.value).to eq('Peakwine')
      expect(drifted.reload.locked).to be false
      expect(locked_row.reload.value).to eq('https://peakwine.id')
      expect(locked_row.reload.locked).to be false
    end

    it 'skips with an info log when the database is unavailable' do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)

      result = nil
      expect { result = described_class.apply! }.not_to raise_error
      expect(result).to be false
      expect(Rails.logger).to have_received(:info).with(/skipped \(database unavailable/)
      expect(Rails.logger).not_to have_received(:error)
    end
  end

  describe 'HUB_JOB_NO_OP' do
    it 'stops every perform path of Internal::CheckNewVersionsJob before any hub call or config write' do
      job_class = Class.new(Internal::CheckNewVersionsJob)
      job_class.prepend(described_class::HUB_JOB_NO_OP)
      allow(Rails.logger).to receive(:info)

      expect(ChatwootHub).not_to receive(:sync_with_hub)
      expect(InstallationConfig).not_to receive(:find_or_initialize_by)
      expect { job_class.new.perform }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with(/skipped/)
    end
  end
end
