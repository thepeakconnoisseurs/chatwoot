# frozen_string_literal: true

# peakwine: restrict-waba-templates — ACL row = (inbox, template_name, custom_role).
# Template tetap jsonb milik channel (disync dari Meta); assignment hidup di tabel
# fork ini. Lihat docs/brief/restrict-waba-templates.md §4.2.
# Penegakan akses TIDAK lewat model ini — semua cek lewat Peakwine::TemplateAccess.
module Peakwine
  class TemplatePermission < ApplicationRecord
    belongs_to :account
    belongs_to :inbox

    validates :template_name, presence: true
    validates :custom_role_id, uniqueness: { scope: %i[inbox_id template_name] }
    validate :custom_role_must_belong_to_account
    validate :inbox_must_be_whatsapp_cloud

    scope :for_inbox, ->(inbox) { where(inbox_id: inbox.id) }

    private

    # Asosiasi custom_roles hanya ada saat modul EE terload (F19). Guard agar
    # CRUD jadi error validasi (bukan NoMethodError/500) bila EE tidak aktif.
    # Penegakan akses TIDAK lewat sini (lihat §5) — inti gate tetap hidup
    # apa pun status EE (hanya butuh kolom OSS custom_role_id).
    def custom_role_must_belong_to_account
      unless account.respond_to?(:custom_roles)
        return errors.add(:custom_role_id, :invalid)
      end

      return if account.custom_roles.exists?(id: custom_role_id)

      errors.add(:custom_role_id, :invalid)
    end

    def inbox_must_be_whatsapp_cloud
      return if inbox&.channel.is_a?(Channel::Whatsapp)

      errors.add(:inbox_id, :invalid)
    end
  end
end
