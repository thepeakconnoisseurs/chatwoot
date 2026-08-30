# fork: restrict-waba-templates — factory cermin untuk tabel ACL (spec only)
FactoryBot.define do
  factory :peakwine_template_permission, class: 'Peakwine::TemplatePermission' do
    transient do
      parent_account { nil }
    end

    account { parent_account || create(:account) }
    inbox do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          sync_templates: false, validate_provider_config: false)
      channel.inbox
    end
    sequence(:template_name) { |n| "template_#{n}" }
    custom_role_id { create(:custom_role, account: account).id }
  end
end
