# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactPolicy do
  let(:account) { create(:account) }
  let(:administrator) { create(:account_user, account: account, role: :administrator) }
  let(:agent) { create(:account_user, account: account, role: :agent) }
  let(:custom_role) { create(:custom_role, account: account, permissions: %w[conversation_manage]) }
  let(:restricted_agent) { create(:account_user, account: account, role: :agent, custom_role: custom_role) }

  def policy_for(account_user)
    described_class.new({ user: account_user.user, account: account, account_user: account_user }, nil)
  end

  %i[update? create? avatar? destroy_custom_attributes? contactable_inboxes?].each do |action|
    describe "##{action}" do
      it 'denies custom-role agents without contact_manage' do
        expect(policy_for(restricted_agent).public_send(action)).to be(false)
      end

      it 'permits administrators' do
        expect(policy_for(administrator).public_send(action)).to be(true)
      end

      it 'permits plain agents' do
        expect(policy_for(agent).public_send(action)).to be(true)
      end
    end
  end

  describe 'permitted actions stay unchanged' do
    it 'permits index/show/search for every viewer' do
      [administrator, agent, restricted_agent].each do |viewer|
        policy = policy_for(viewer)

        expect(policy.index?).to be(true)
        expect(policy.show?).to be(true)
        expect(policy.search?).to be(true)
      end
    end

    it 'keeps export and destroy administrator-only in CE' do
      expect(policy_for(administrator).export?).to be(true)
      expect(policy_for(agent).export?).to be(false)
      expect(policy_for(administrator).destroy?).to be(true)
      expect(policy_for(agent).destroy?).to be(false)
    end
  end
end
