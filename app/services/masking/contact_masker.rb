# frozen_string_literal: true

module Masking::ContactMasker
  PHONE_VISIBLE_PREFIX = 6   # "+62811"
  PHONE_STARS = '*****'
  EMAIL_VISIBLE_PREFIX = 2   # "pe"
  EMAIL_STARS = '***'
  # string dianggap nomor jika diawali + lalu digit, atau digit murni (boleh spasi/-/./()
  PHONE_LIKE = /\A\+?\d[\d\s\-().]{5,}\z/

  module_function

  # --- penentu akses -------------------------------------------------------
  # TRUE = penonton ini TIDAK boleh melihat data asli.
  # nil account_user (job/websocket tanpa konteks request) => restricted (safe default)
  def restricted?(account_user)
    return true if account_user.nil?

    account_user.role == 'agent' &&
      account_user.custom_role_id.present? &&
      account_user.custom_role.permissions.exclude?('contact_manage')
  end

  # --- transformer ---------------------------------------------------------
  def mask_phone(raw)
    s = raw.to_s.strip
    return s if s.blank?

    prefix = s[0, PHONE_VISIBLE_PREFIX]
    "#{prefix}#{PHONE_STARS}"
  end

  def mask_email(raw)
    s = raw.to_s.strip
    return s if s.blank? || !s.include?('@')

    local, domain = s.split('@', 2)
    "#{local[0, EMAIL_VISIBLE_PREFIX]}#{EMAIL_STARS}@#{domain}"
  end

  def mask_name_if_phone(raw)
    s = raw.to_s.strip
    s.match?(PHONE_LIKE) ? mask_phone(s) : s
  end

  def mask_source_id(raw)
    s = raw.to_s.strip
    s.match?(PHONE_LIKE) ? mask_phone(s) : s   # email-based source_id ikut dicek
  end
end
