<script setup>
import { computed, onActivated, onDeactivated, ref } from 'vue';
import { picoSearch } from '@chatwoot/pico-search';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { INBOX_TYPES, TWILIO_CHANNEL_MEDIUM } from 'dashboard/helper/inbox';
import InboxesAPI from 'dashboard/api/inboxes';
import TemplatePermissionsAPI from 'dashboard/api/templatePermissions';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplateCard from './TemplateCard.vue';
import TemplatePreviewDrawer from './TemplatePreviewDrawer.vue';
import {
  formatTemplateDate,
  formatTemplateLanguage,
  groupTemplates,
  templateTypeKey,
} from './templateUtils';

const FUZZY_SEARCH_KEYS = [
  { name: 'name', weight: 4 },
  'category',
  'language',
  'status',
  'inboxNames',
  'searchableContent',
];

const TEMPLATE_LEARN_MORE_URL =
  'https://www.chatwoot.com/hc/user-guide/articles/1754940076-whatsapp-templates';

const store = useStore();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
const templates = ref([]);
const searchQuery = ref('');
const selectedInboxId = ref('all');
const selectedLanguage = ref('all');
const selectedType = ref('all');
const selectedTemplate = ref(null);
const openFilterMenu = ref(null);
const previewPanelRef = ref(null);
const templateRecordsByInboxId = new Map();
const lastSyncAttemptsByInboxId = ref({});
const isSyncing = ref(false);
// fork: restrict-waba-templates — ACL state (§6 T7)
const customRoles = useMapGetter('customRole/getCustomRoles');
const roleIdsByInboxAndName = ref({});
const permissionsPayloadByInboxId = ref({});
const orphanNamesByInboxId = ref({});
const isSavingRoles = ref(false);
const {
  run: runTemplateRequest,
  abort: abortTemplateRequest,
  isPending: isLoading,
} = useAbortableRequest();

const hasTemplates = computed(() => templates.value.length > 0);

const lastSyncAttemptAt = computed(() => {
  const timestamps = Object.values(lastSyncAttemptsByInboxId.value)
    .filter(Boolean)
    .map(value => new Date(value).getTime())
    .filter(Number.isFinite);

  return timestamps.length ? new Date(Math.max(...timestamps)) : null;
});

const typeLabels = computed(() => ({
  TEXT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.TEXT'),
  IMAGE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.IMAGE'),
  VIDEO: t('WHATSAPP_TEMPLATE_MGMT.TYPES.VIDEO'),
  DOCUMENT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.DOCUMENT'),
  MEDIA: t('WHATSAPP_TEMPLATE_MGMT.TYPES.MEDIA'),
  QUICK_REPLY: t('WHATSAPP_TEMPLATE_MGMT.TYPES.QUICK_REPLY'),
  CALL_TO_ACTION: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CALL_TO_ACTION'),
  CATALOG: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CATALOG'),
  COPY_CODE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.COPY_CODE'),
}));

const whatsappInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP ||
      (inbox.channel_type === INBOX_TYPES.TWILIO &&
        inbox.medium === TWILIO_CHANNEL_MEDIUM.WHATSAPP)
  )
);

// fork: restrict-waba-templates — Cloud WhatsApp only (Twilio WA out of scope)
const cloudWhatsappInboxes = computed(() =>
  inboxes.value.filter(inbox => inbox.channel_type === INBOX_TYPES.WHATSAPP)
);

const inboxOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_INBOXES'),
  },
  ...whatsappInboxes.value.map(inbox => ({
    value: String(inbox.id),
    label: inbox.name,
  })),
]);

const languageOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_LANGUAGES'),
  },
  ...[...new Set(templates.value.map(template => template.language))]
    .filter(Boolean)
    .sort()
    .map(language => ({
      value: language,
      label: formatTemplateLanguage(language),
    })),
]);

const typeOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_TYPES'),
  },
  ...[...new Set(templates.value.map(templateTypeKey))]
    .map(type => ({
      value: type,
      label: typeLabels.value[type],
    }))
    .sort((first, second) => first.label.localeCompare(second.label)),
]);

const filterMenus = computed(() =>
  [
    {
      key: 'inbox',
      icon: 'i-lucide-inbox',
      options: inboxOptions.value,
      active: selectedInboxId.value,
    },
    {
      key: 'language',
      icon: 'i-lucide-languages',
      options: languageOptions.value,
      active: selectedLanguage.value,
    },
    {
      key: 'type',
      icon: 'i-lucide-layout-template',
      options: typeOptions.value,
      active: selectedType.value,
    },
  ].map(menu => {
    const items = menu.options.map(option => ({
      ...option,
      action: menu.key,
      isSelected: option.value === menu.active,
    }));

    return {
      ...menu,
      items,
      selected: items.find(item => item.isSelected) || items[0],
    };
  })
);

const closeFilterMenu = () => {
  openFilterMenu.value = null;
};

const toggleFilterMenu = key => {
  openFilterMenu.value = openFilterMenu.value === key ? null : key;
};

const openPreview = template => {
  selectedTemplate.value = template;
  previewPanelRef.value?.open();
};

const handleFilterAction = ({ action, value }) => {
  closeFilterMenu();
  if (action === 'inbox') selectedInboxId.value = value;
  else if (action === 'language') selectedLanguage.value = value;
  else selectedType.value = value;
};

const filteredTemplates = computed(() => {
  let records = templates.value;

  if (selectedInboxId.value !== 'all') {
    records = records.filter(template =>
      template.inboxes.some(inbox => String(inbox.id) === selectedInboxId.value)
    );
  }

  if (selectedLanguage.value !== 'all') {
    records = records.filter(
      template => template.language === selectedLanguage.value
    );
  }

  if (selectedType.value !== 'all') {
    records = records.filter(
      template => templateTypeKey(template) === selectedType.value
    );
  }

  const query = searchQuery.value.trim();
  if (!query) return records;

  const normalizedQuery = query.toLowerCase();
  const contentMatches = records.filter(template =>
    [template.name, template.searchableContent].some(value =>
      value?.toLowerCase().includes(normalizedQuery)
    )
  );
  if (contentMatches.length) return contentMatches;

  return picoSearch(records, query, FUZZY_SEARCH_KEYS);
});

const showSearch = computed(() =>
  Boolean(filteredTemplates.value.length || searchQuery.value)
);

const fetchTemplates = async () => {
  try {
    await runTemplateRequest(async signal => {
      const didFetchInboxes = await store.dispatch('inboxes/get');
      if (!didFetchInboxes) throw new Error();
      if (signal.aborted) return;

      const inboxesToFetch = [...whatsappInboxes.value];
      const responses = await Promise.allSettled(
        inboxesToFetch.map(async inbox => {
          const { data } = await InboxesAPI.getMessageTemplates(
            inbox.id,
            {},
            { signal }
          );

          if (!Array.isArray(data.payload)) {
            throw new TypeError();
          }

          return {
            inboxId: inbox.id,
            lastSyncAttemptAt: data.meta?.last_sync_attempt_at,
            records: data.payload.map(template => ({
              template,
              inbox,
              lastUpdatedAt: data.meta?.last_sync_attempt_at,
            })),
          };
        })
      );

      if (signal.aborted) return;

      const successfulResponses = responses.filter(
        response => response.status === 'fulfilled'
      );
      const activeInboxIds = new Set(inboxesToFetch.map(inbox => inbox.id));
      const nextLastSyncAttempts = {
        ...lastSyncAttemptsByInboxId.value,
      };

      templateRecordsByInboxId.forEach((_, inboxId) => {
        if (!activeInboxIds.has(inboxId)) {
          templateRecordsByInboxId.delete(inboxId);
          delete nextLastSyncAttempts[inboxId];
        }
      });
      successfulResponses.forEach(({ value }) => {
        templateRecordsByInboxId.set(value.inboxId, value.records);
        nextLastSyncAttempts[value.inboxId] = value.lastSyncAttemptAt;
      });
      lastSyncAttemptsByInboxId.value = nextLastSyncAttempts;
      templates.value = groupTemplates(
        [...templateRecordsByInboxId.values()].flat()
      );

      if (
        !inboxOptions.value.some(({ value }) => value === selectedInboxId.value)
      )
        selectedInboxId.value = 'all';
      if (
        !languageOptions.value.some(
          ({ value }) => value === selectedLanguage.value
        )
      )
        selectedLanguage.value = 'all';
      if (!typeOptions.value.some(({ value }) => value === selectedType.value))
        selectedType.value = 'all';

      if (responses.some(response => response.status === 'rejected')) {
        const errorMessage = successfulResponses.length
          ? t('WHATSAPP_TEMPLATE_MGMT.PARTIAL_FETCH_ERROR')
          : t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR');
        useAlert(errorMessage);
      }
    });
  } catch {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR'));
  }
};

const syncTemplates = async () => {
  if (isSyncing.value) return;

  isSyncing.value = true;

  const responses = await Promise.allSettled(
    whatsappInboxes.value.map(inbox =>
      store.dispatch('inboxes/syncTemplates', inbox.id)
    )
  );
  const failedCount = responses.filter(
    response => response.status === 'rejected'
  ).length;

  if (!failedCount) {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.SYNC_SUCCESS'));
  } else if (failedCount < responses.length) {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.PARTIAL_SYNC_ERROR'));
  } else {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.SYNC_ERROR'));
  }

  isSyncing.value = false;
};

// fork: restrict-waba-templates — load ACL per Cloud inbox (parallel GET),
// keep the raw payload per inbox (PUT is replace-all) + orphan names.
const fetchTemplatePermissions = async () => {
  try {
    const didFetchInboxes = await store.dispatch('inboxes/get');
    if (!didFetchInboxes) throw new Error();

    const responses = await Promise.allSettled(
      cloudWhatsappInboxes.value.map(inbox =>
        TemplatePermissionsAPI.get(inbox.id)
      )
    );

    const nextRoleIds = {};
    const nextPayloads = {};
    const nextOrphans = {};
    responses.forEach((response, index) => {
      if (response.status !== 'fulfilled') return;

      const inboxId = cloudWhatsappInboxes.value[index].id;
      const payload = response.value.data.payload || [];
      nextPayloads[inboxId] = payload;
      nextRoleIds[inboxId] = {};
      payload.forEach(entry => {
        nextRoleIds[inboxId][entry.template_name] = entry.role_ids || [];
      });
      nextOrphans[inboxId] = response.value.data.meta?.orphan_names || [];
    });
    roleIdsByInboxAndName.value = nextRoleIds;
    permissionsPayloadByInboxId.value = nextPayloads;
    orphanNamesByInboxId.value = nextOrphans;

    if (responses.some(response => response.status === 'rejected')) {
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.ROLES.FETCH_ERROR'));
    }
  } catch {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.ROLES.FETCH_ERROR'));
  }
};

const orphanAssignmentCount = computed(() => {
  const names = new Set();
  Object.values(orphanNamesByInboxId.value).forEach(namesForInbox => {
    namesForInbox.forEach(name => names.add(name));
  });
  return names.size;
});

// MVP (brief §6 T7 / E4): union across inboxes holding the template — saving
// applies the chosen set to every one of those inboxes.
const selectedRoleIdsForTemplate = template => {
  const union = new Set();
  template.inboxes
    .filter(inbox => inbox.channel_type === INBOX_TYPES.WHATSAPP)
    .forEach(inbox => {
      (roleIdsByInboxAndName.value[inbox.id]?.[template.name] || []).forEach(
        roleId => union.add(roleId)
      );
    });
  return [...union];
};

const handleSaveRoles = async ({ template, roleIds }) => {
  if (isSavingRoles.value) return;

  const targetInboxes = template.inboxes.filter(
    inbox => inbox.channel_type === INBOX_TYPES.WHATSAPP
  );
  // Never PUT a blind [] — an inbox whose GET failed has no stored payload and
  // a replace-all [] would wipe every assignment on it. Skip and warn instead.
  const inboxesToSave = targetInboxes.filter(
    inbox => permissionsPayloadByInboxId.value[inbox.id]
  );
  const skippedCount = targetInboxes.length - inboxesToSave.length;

  if (!inboxesToSave.length) {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.ROLES.SAVE_ERROR'));
    return;
  }

  isSavingRoles.value = true;
  try {
    const responses = await Promise.allSettled(
      inboxesToSave.map(inbox => {
        const entries = permissionsPayloadByInboxId.value[inbox.id].map(
          entry => ({
            template_name: entry.template_name,
            role_ids:
              entry.template_name === template.name
                ? roleIds
                : entry.role_ids || [],
          })
        );
        return TemplatePermissionsAPI.replace(inbox.id, entries);
      })
    );

    if (responses.some(response => response.status === 'rejected')) {
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.ROLES.SAVE_ERROR'));
    } else if (skippedCount) {
      useAlert(
        t('WHATSAPP_TEMPLATE_MGMT.ROLES.SAVE_SKIPPED', { n: skippedCount })
      );
    } else {
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.ROLES.SAVE_SUCCESS'));
    }
    // Re-fetch so the UI reflects server state after partial failures too.
    await fetchTemplatePermissions();
  } catch {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.ROLES.SAVE_ERROR'));
  } finally {
    isSavingRoles.value = false;
  }
};

onActivated(() => {
  fetchTemplates();
  store.dispatch('customRole/getCustomRole');
  fetchTemplatePermissions();
});
onDeactivated(abortTemplateRequest);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('WHATSAPP_TEMPLATE_MGMT.LOADING')"
    :no-records-found="!templates.length"
    :no-records-message="$t('WHATSAPP_TEMPLATE_MGMT.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('WHATSAPP_TEMPLATE_MGMT.TITLE')"
        :search-placeholder="
          showSearch ? $t('WHATSAPP_TEMPLATE_MGMT.SEARCH_PLACEHOLDER') : ''
        "
      >
        <template #description>
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DESCRIPTION') }}
          <a
            :href="TEMPLATE_LEARN_MORE_URL"
            class="text-sm font-medium text-n-blue-11 hover:underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ $t('WHATSAPP_TEMPLATE_MGMT.KNOW_MORE') }}
          </a>
          <span
            v-if="lastSyncAttemptAt"
            class="block mt-1 text-xs text-n-slate-10"
          >
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.LAST_SYNC_ATTEMPT', {
                date: formatTemplateDate(lastSyncAttemptAt),
              })
            }}
          </span>
          <!-- fork: restrict-waba-templates — stale assignment awareness (§6 T7) -->
          <span
            v-if="orphanAssignmentCount"
            class="block mt-1 text-xs text-n-amber-11"
          >
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.ROLES.ORPHAN_COUNT', {
                n: orphanAssignmentCount,
              })
            }}
          </span>
        </template>
        <template #tabs>
          <div
            v-if="hasTemplates"
            v-on-click-outside="closeFilterMenu"
            class="flex items-center gap-2"
          >
            <div v-for="menu in filterMenus" :key="menu.key" class="relative">
              <Button
                :icon="menu.icon"
                color="slate"
                size="sm"
                :class="{ 'bg-n-slate-9/10': openFilterMenu === menu.key }"
                @click="toggleFilterMenu(menu.key)"
              >
                <span class="min-w-0 truncate">{{ menu.selected.label }}</span>
                <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
              </Button>
              <DropdownMenu
                v-if="openFilterMenu === menu.key"
                :menu-items="menu.items"
                class="mt-2 min-w-52 top-full ltr:left-0 rtl:right-0"
                @action="handleFilterAction"
              />
            </div>
          </div>
        </template>
        <template v-if="filteredTemplates.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.COUNT', {
                n: filteredTemplates.length,
              })
            }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('WHATSAPP_TEMPLATE_MGMT.SYNC_TEMPLATES')"
            icon="i-lucide-refresh-cw"
            color="slate"
            size="sm"
            :is-loading="isSyncing"
            :disabled="!whatsappInboxes.length || isSyncing"
            @click="syncTemplates"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div
        v-if="!filteredTemplates.length"
        class="flex items-center justify-center p-8"
      >
        <span class="text-base text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.NO_RESULTS') }}
        </span>
      </div>

      <div v-else class="border-t divide-y divide-n-weak border-n-weak">
        <TemplateCard
          v-for="template in filteredTemplates"
          :key="template.key"
          :template="template"
          :roles="customRoles"
          :selected-role-ids="selectedRoleIdsForTemplate(template)"
          :is-saving-roles="isSavingRoles"
          @preview="openPreview(template)"
          @save-roles="handleSaveRoles"
        />
      </div>
    </template>

    <TemplatePreviewDrawer ref="previewPanelRef" :template="selectedTemplate" />
  </SettingsLayout>
</template>
