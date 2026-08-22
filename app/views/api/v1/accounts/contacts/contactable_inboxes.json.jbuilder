json.payload do
  json.array! @contactable_inboxes do |contactable_inbox|
    json.inbox do
      json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: contactable_inbox[:inbox]
    end
    restricted = Masking::ContactMasker.restricted?(Current.account_user)
    json.source_id restricted ? Masking::ContactMasker.mask_source_id(contactable_inbox[:source_id]) : contactable_inbox[:source_id]
  end
end
