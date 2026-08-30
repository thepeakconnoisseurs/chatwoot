# frozen_string_literal: true

# peakwine: restrict-waba-templates — SATU helper untuk semua cek akses template
# WhatsApp (docs/brief/restrict-waba-templates.md §5). Dipakai oleh:
#   - _inbox.json.jbuilder        (filter payload inbox, web + mobile)
#   - whatsapp_health_management  (filter endpoint message_templates, Cloud only)
#   - Messages::MessageBuilder    (gerbang kirim — enforcement sebenarnya)
# Dilarang menulis ulang logika custom_role_id/query di tempat lain (aturan emas).
module Peakwine::TemplateAccess
  class Denied < StandardError; end

  module_function

  # --- pertanyaan tunggal: bolehkah viewer MENGGUNAKAN template ini? -------
  def allowed?(account_user, inbox, template_name)
    return true if account_user&.administrator?
    return false if account_user.blank? || template_name.blank?
    return false if account_user.custom_role_id.blank?

    Peakwine::TemplatePermission.where(
      inbox_id: inbox.id,
      template_name: template_name.to_s,
      custom_role_id: account_user.custom_role_id
    ).exists?
  end

  # --- filter daftar template (array hash dari channel.message_templates) --
  def filter_templates(account_user, inbox, templates)
    return templates if account_user&.administrator?
    return [] if account_user.blank? || account_user.custom_role_id.blank?
    return templates unless templates.is_a?(Array)

    allowed_names = Peakwine::TemplatePermission
                    .where(inbox_id: inbox.id, custom_role_id: account_user.custom_role_id)
                    .pluck(:template_name).to_set

    templates.select { |t| allowed_names.include?(t['name']) }
  end

  # --- gerbang kirim: dipanggil dari Messages::MessageBuilder (§6 T5) ------
  # Bypass: AgentBot & automation rule (hasil konfigurasi admin).
  # Deny-safe: user tanpa keanggotaan account → ditolak.
  # URUTAN CEK WAJIB APA ADANYA: name.blank? paling awal — automation rule
  # dan campaign builder memanggil builder dengan user NIL (F8, F16);
  # mereka hanya selamat karena bukan pesan template.
  def enforce_send!(user, conversation, template_params, automation: false)
    name = template_name_from(template_params)
    return if name.blank?                # bukan pesan template
    # Cloud WA only — Twilio WhatsApp di luar scope (E10/F18): baris ACL tidak
    # mungkin ada di sana dan lapisan daftar memang tidak difilter (T3 guard).
    return unless conversation.inbox.channel.is_a?(Channel::Whatsapp)
    return if user.is_a?(AgentBot)
    return if automation

    # Deny-safe: user blank dengan nama template (bentuk caller masa depan)
    # ditolak eksplisit, bukan NoMethodError → 500.
    raise Denied, I18n.t('errors.whatsapp_template_access_denied') if user.blank?

    account_user = user.account_users.find_by(account_id: conversation.account_id)
    return if account_user&.administrator?

    return if allowed?(account_user, conversation.inbox, name)

    raise Denied, I18n.t('errors.whatsapp_template_access_denied')
  end

  # v2: JANGAN pakai to_h (raise pada unpermitted Parameters — F14).
  # Bracket access bekerja untuk Hash & ActionController::Parameters.
  def template_name_from(template_params)
    return if template_params.blank?

    name = begin
      template_params['name'].presence || template_params[:name].presence
    rescue StandardError
      nil
    end
    return name if name.present?

    hash = template_params.to_unsafe_h if template_params.respond_to?(:to_unsafe_h)
    hash ||= {}
    (hash['name'] || hash[:name]).presence
  rescue StandardError
    nil
  end
end
