class ContactPolicy < ApplicationPolicy
  def index?
    true
  end

  def active?
    true
  end

  def import?
    @account_user.administrator?
  end

  def export?
    @account_user.administrator?
  end

  def search?
    true
  end

  def filter?
    true
  end

  def update?
    return false if custom_role_without_contact_manage?

    true
  end

  def contactable_inboxes?
    true
  end

  def destroy_custom_attributes?
    return false if custom_role_without_contact_manage?

    true
  end

  def show?
    true
  end

  def create?
    return false if custom_role_without_contact_manage?

    true
  end

  def avatar?
    return false if custom_role_without_contact_manage?

    true
  end

  def destroy?
    @account_user.administrator?
  end

  private

  # peakwine local patch: a custom-role agent whose role lacks the
  # 'contact_manage' permission must not be able to mutate contact records
  # (e.g. rename from the conversation contact panel).
  def custom_role_without_contact_manage?
    @account_user&.role == 'agent' && @account_user.custom_role_id.present? &&
      @account_user.custom_role.permissions.exclude?('contact_manage')
  end
end

ContactPolicy.prepend_mod_with('ContactPolicy')
