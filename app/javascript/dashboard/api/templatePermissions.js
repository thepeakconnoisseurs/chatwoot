/* global axios */
import ApiClient from './ApiClient';

// fork: restrict-waba-templates — admin-only ACL CRUD nested under inboxes
// (docs/brief/restrict-waba-templates.md §6 T6)
class InboxTemplatePermissions extends ApiClient {
  constructor() {
    // URL: /api/v1/accounts/{accountId}/inboxes/{inboxId}/template_permissions
    super('inboxes', { accountScoped: true });
  }

  get(inboxId) {
    return axios.get(`${this.url}/${inboxId}/template_permissions`);
  }

  replace(inboxId, templatePermissions) {
    return axios.put(`${this.url}/${inboxId}/template_permissions`, {
      template_permissions: templatePermissions,
    });
  }
}

export default new InboxTemplatePermissions();
