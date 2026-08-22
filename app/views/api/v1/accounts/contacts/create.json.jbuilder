json.payload do
  json.contact do
    json.partial! 'api/v1/models/contact', formats: [:json], resource: @contact, with_contact_inboxes: true
  end
  json.contact_inbox do
    json.inbox @contact_inbox&.inbox
    restricted = Masking::ContactMasker.restricted?(Current.account_user)
    source_id = @contact_inbox&.source_id
    json.source_id restricted ? Masking::ContactMasker.mask_source_id(source_id) : source_id
  end
end
