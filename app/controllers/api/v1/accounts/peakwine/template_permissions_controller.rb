# frozen_string_literal: true

# peakwine: restrict-waba-templates — admin-only CRUD untuk ACL template WA
# (docs/brief/restrict-waba-templates.md §6 T6). Nested di bawah inbox:
#   GET  /api/v1/accounts/{account_id}/inboxes/{inbox_id}/template_permissions
#   PUT  ... (replace-all atomik per inbox, 204)
# Otorisasi: check_admin_authorization? (dengan `?` — F17) → raise Pundit::NotAuthorizedError,
# dirender 401 oleh RequestExceptionHandler (render_unauthorized).
# Konstanta model WAJIB prefix `::` — namespace controller ini (Api::V1::Accounts::Peakwine)
# membuat `Peakwine::...` resolve relatif ke namespace sendiri → NameError (insiden 2026-08-31).
module Api
  module V1
    module Accounts
      module Peakwine
        class TemplatePermissionsController < Api::V1::Accounts::BaseController
          before_action :check_admin_authorization?
          before_action :inbox

          def show
            rows = ::Peakwine::TemplatePermission.for_inbox(inbox).order(:template_name)
            role_ids_by_name = rows.group_by(&:template_name).transform_values { |group| group.map(&:custom_role_id).sort }

            @payload = channel_template_names.map { |name| { template_name: name, role_ids: role_ids_by_name[name] || [] } }
            @orphan_names = rows.map(&:template_name).uniq - channel_template_names
          end

          def update
            return render_could_not_create_error('template_permissions must be an array') unless params[:template_permissions].is_a?(Array)

            entries = permission_params
            unknown = unknown_template_names(entries)
            if unknown.present?
              return render_could_not_create_error(
                "Unknown WhatsApp template: #{unknown.join(', ')} (only orphan entries may be sent with empty role_ids)"
              )
            end

            ActiveRecord::Base.transaction do
              ::Peakwine::TemplatePermission.for_inbox(inbox).delete_all
              entries.each do |entry|
                entry[:role_ids].each do |role_id|
                  ::Peakwine::TemplatePermission.create!(
                    account: Current.account,
                    inbox: inbox,
                    template_name: entry[:template_name],
                    custom_role_id: role_id
                  )
                end
              end
            end
            head :no_content
          rescue ActiveRecord::RecordInvalid => e
            render_could_not_create_error(e.record.errors.full_messages.to_sentence)
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey => e
            # race replace-all konkuren / role dihapus di tengah transaksi → 422, bukan 500
            render_could_not_create_error(e.message)
          end

          private

          def inbox
            @inbox ||= Current.account.inboxes.find(params[:inbox_id])
          end

          # [{ template_name: 'x', role_ids: [3, 5] }, ...] — role_ids dinormalisasi
          # ke array integer unik; entri non-hash dan entri tanpa nama diabaikan.
          def permission_params
            params.require(:template_permissions).filter_map do |entry|
              next unless entry.respond_to?(:[])

              template_name = entry[:template_name].to_s.presence
              next unless template_name

              {
                template_name: template_name,
                role_ids: Array(entry[:role_ids]).reject(&:blank?).map { |id| id.to_i }.uniq
              }
            end
          end

          # Nama yang boleh di-assign = nama yang masih ada di channel. Entri
          # dengan role kosong untuk nama yatim = orphan cleanup (diizinkan —
          # replace-all menghapusnya tanpa membuat baris baru).
          def unknown_template_names(entries)
            entries.reject { |entry| entry[:role_ids].blank? }
                   .map { |entry| entry[:template_name] }
                   .reject { |name| channel_template_names.include?(name) }
                   .uniq
          end

          def channel_template_names
            templates = inbox.channel.try(:message_templates)
            return [] unless templates.is_a?(Array)

            templates.filter_map { |template| template['name'].presence }.uniq
          end
        end
      end
    end
  end
end
