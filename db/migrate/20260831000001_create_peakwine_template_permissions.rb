# fork: restrict-waba-templates — whitelist ACL table (docs/brief/restrict-waba-templates.md §4.1)
class CreatePeakwineTemplatePermissions < ActiveRecord::Migration[7.1]
  def change
    # on_delete: :cascade WAJIB (audit v2):
    #  - Inbox dihapus admin → assignment ikut terhapus (tanpa ini: FK violation → 500;
    #    upstream sendiri pakai dependent: :destroy_async utk semua asosiasi inbox)
    #  - custom role dihapus (EE CustomRolesController#destroy! tanpa pembersihan)
    #    → assignment role itu otomatis dicabut = perilaku default-deny yang benar
    create_table :peakwine_template_permissions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :template_name, null: false
      t.bigint :custom_role_id, null: false
      t.timestamps
    end

    add_index :peakwine_template_permissions, [:inbox_id, :template_name, :custom_role_id],
              unique: true, name: 'idx_peakwine_tp_on_inbox_template_role'
    add_index :peakwine_template_permissions, [:account_id, :custom_role_id]
    add_foreign_key :peakwine_template_permissions, :custom_roles, on_delete: :cascade
  end
end
