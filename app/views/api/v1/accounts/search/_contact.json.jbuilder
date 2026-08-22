restricted = Masking::ContactMasker.restricted?(Current.account_user)
json.email restricted ? Masking::ContactMasker.mask_email(contact.email) : contact.email
json.id contact.id
json.name restricted ? Masking::ContactMasker.mask_name_if_phone(contact.name) : contact.name
json.phone_number restricted ? Masking::ContactMasker.mask_phone(contact.phone_number) : contact.phone_number
json.identifier contact.identifier
json.additional_attributes contact.additional_attributes
json.last_activity_at contact.last_activity_at&.to_i
