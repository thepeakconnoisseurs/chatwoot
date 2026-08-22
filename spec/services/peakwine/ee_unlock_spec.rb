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

  describe '.apply!' do
    before do
      allow(GlobalConfig).to receive(:clear_cache)
      # InstallationConfig pings GlobalConfig.clear_cache from after_commit on
      # every save; silence the callback so received counts prove apply!'s own call.
      InstallationConfig.skip_callback(:commit, :after, :clear_cache)
    end

    after do
      InstallationConfig.set_callback(:commit, :after, :clear_cache)
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
    end

    it 'raises quantity to the floor but keeps higher values' do
      InstallationConfig.create!(name: 'INSTALLATION_PRICING_PLAN_QUANTITY', value: 500)

      described_class.apply!

      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY').value).to eq(500)
    end

    it 'never touches branding InstallationConfigs while BRAND_SNAPSHOT is empty' do
      expect(described_class::BRAND_SNAPSHOT).to be_empty
      allow(InstallationConfig).to receive(:find_or_initialize_by).and_call_original

      described_class.apply!

      expect(InstallationConfig).to have_received(:find_or_initialize_by).exactly(:twice)
      expect(InstallationConfig).to have_received(:find_or_initialize_by).with(name: 'INSTALLATION_PRICING_PLAN')
      expect(InstallationConfig).to have_received(:find_or_initialize_by).with(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')
    end

    it 'logs and swallows DB failures so the boot continues' do
      allow(InstallationConfig).to receive(:find_or_initialize_by).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Rails.logger).to receive(:error)

      result = nil
      expect { result = described_class.apply! }.not_to raise_error
      expect(result).to be false
      expect(Rails.logger).to have_received(:error).with(/apply! failed/)
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
