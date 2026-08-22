restricted = Masking::ContactMasker.restricted?(Current.account_user)
json.source_id restricted ? Masking::ContactMasker.mask_source_id(resource.source_id) : resource.source_id
json.inbox do
  json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: resource.inbox
end
