<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// fork: restrict-waba-templates — multi-select custom role per template card
// (docs/brief/restrict-waba-templates.md §6 T7). Page is administrator-only
// (templates.routes.js `permissions: ['administrator']`) and the API is
// admin-only server-side, so no extra role check is needed here.
const props = defineProps({
  template: {
    type: Object,
    required: true,
  },
  roles: {
    type: Array,
    default: () => [],
  },
  selectedRoleIds: {
    type: Array,
    default: () => [],
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['save']);
const { t } = useI18n();

const isOpen = ref(false);
const draftRoleIds = ref([]);

// Watch a value-stable key (joined ids), not the array reference — a parent
// re-render with a fresh array must not clobber in-progress checkbox drafts.
watch(
  () => (props.selectedRoleIds || []).join(','),
  () => {
    draftRoleIds.value = [...(props.selectedRoleIds || [])];
  },
  { immediate: true }
);

const selectedRoleNames = computed(() =>
  props.roles
    .filter(role => draftRoleIds.value.includes(role.id))
    .map(role => role.name)
);

const summaryLabel = computed(() => {
  if (!draftRoleIds.value.length)
    return t('WHATSAPP_TEMPLATE_MGMT.ROLES.ADMIN_ONLY');
  return selectedRoleNames.value.join(', ');
});

const close = () => {
  isOpen.value = false;
};

const toggle = () => {
  isOpen.value = !isOpen.value;
};

const toggleRole = roleId => {
  draftRoleIds.value = draftRoleIds.value.includes(roleId)
    ? draftRoleIds.value.filter(id => id !== roleId)
    : [...draftRoleIds.value, roleId];
};

const save = () => {
  emit('save', {
    template: props.template,
    roleIds: [...draftRoleIds.value],
  });
  close();
};
</script>

<template>
  <div
    v-on-click-outside="close"
    class="relative shrink-0"
    @click.stop
    @keydown.stop
  >
    <Button
      :icon="draftRoleIds.length ? 'i-lucide-users' : 'i-lucide-lock'"
      color="slate"
      size="sm"
      :is-loading="isSaving"
      @click="toggle"
    >
      <span class="min-w-0 max-w-40 truncate">
        {{ summaryLabel }}
      </span>
      <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
    </Button>
    <div
      v-if="isOpen"
      class="absolute z-20 p-2 mt-2 border rounded-xl bg-n-panel top-full ltr:right-0 rtl:left-0 border-n-strong shadow-context-menu"
    >
      <div class="flex flex-col gap-1 p-1 min-w-56 max-h-48 overflow-y-auto">
        <span v-if="!roles.length" class="px-2 py-1 text-xs text-n-slate-11">
          {{ t('WHATSAPP_TEMPLATE_MGMT.ROLES.NO_ROLES') }}
        </span>
        <label
          v-for="role in roles"
          :key="role.id"
          class="flex items-center gap-2 px-2 py-1 text-sm rounded-lg cursor-pointer text-n-slate-12 hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            class="rounded size-4 accent-n-blue-11"
            :checked="draftRoleIds.includes(role.id)"
            @change="toggleRole(role.id)"
          />
          <span class="min-w-0 truncate">{{ role.name }}</span>
        </label>
      </div>
      <div class="flex flex-col gap-1 px-2 pt-2 pb-1 border-t border-n-strong">
        <span class="text-xs text-n-slate-11">
          {{ t('WHATSAPP_TEMPLATE_MGMT.ROLES.APPLIES_TO_ALL_INBOXES') }}
        </span>
        <div class="flex justify-end gap-2">
          <Button size="sm" color="slate" @click="close">
            {{ t('WHATSAPP_TEMPLATE_MGMT.ROLES.CANCEL') }}
          </Button>
          <Button size="sm" @click="save">
            {{ t('WHATSAPP_TEMPLATE_MGMT.ROLES.SAVE') }}
          </Button>
        </div>
      </div>
    </div>
  </div>
</template>
