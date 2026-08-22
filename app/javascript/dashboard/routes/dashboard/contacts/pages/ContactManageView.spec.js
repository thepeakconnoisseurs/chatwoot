import { flushPromises, shallowMount } from '@vue/test-utils';
import ContactManageView from './ContactManageView.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  useAlert: vi.fn(),
  getterValues: null,
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  const contact = {
    id: 42,
    name: 'Jane Doe',
    email: 'peakwine@gmail.com',
    phoneNumber: '+6281234567890',
    additionalAttributes: { company_name: 'Acme', city: 'Jakarta' },
  };
  mocks.getterValues = {
    'contacts/getContactById': ref(() => contact),
    'contacts/getUIFlags': ref({
      isFetchingItem: false,
      isMerging: false,
      isUpdating: false,
    }),
  };

  return {
    useStore: () => ({ dispatch: mocks.dispatch }),
    useMapGetter: key => mocks.getterValues[key],
  };
});

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal();

  return {
    ...actual,
    useRoute: () => ({ params: { accountId: 1, contactId: 42 }, query: {} }),
    useRouter: () => ({ push: vi.fn(), back: vi.fn() }),
  };
});

// The sidebar children are irrelevant to the behaviors under test; mocking
// their modules keeps the spec isolated from their heavy editor/graph imports.
vi.mock('dashboard/components-next/Contacts/ContactsDetailsLayout.vue', () => ({
  default: { name: 'ContactsDetailsLayout', template: '<div />' },
}));
vi.mock('dashboard/components-next/Contacts/Pages/ContactDetails.vue', () => ({
  default: { name: 'ContactDetails', template: '<div />' },
}));
vi.mock(
  'dashboard/components-next/Contacts/ContactsSidebar/ContactNotes.vue',
  () => ({
    default: { name: 'ContactNotes', template: '<div />' },
  })
);
vi.mock(
  'dashboard/components-next/Contacts/ContactsSidebar/ContactHistory.vue',
  () => ({
    default: { name: 'ContactHistory', template: '<div />' },
  })
);
vi.mock(
  'dashboard/components-next/Contacts/ContactsSidebar/ContactMedia.vue',
  () => ({
    default: { name: 'ContactMedia', template: '<div />' },
  })
);
vi.mock(
  'dashboard/components-next/Contacts/ContactsSidebar/ContactMerge.vue',
  () => ({
    default: { name: 'ContactMerge', template: '<div />' },
  })
);
vi.mock(
  'dashboard/components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue',
  () => ({
    default: { name: 'ContactCustomAttributes', template: '<div />' },
  })
);

const mountComponent = () => shallowMount(ContactManageView);

const emittedUpdatePayload = () => {
  const updateCall = mocks.dispatch.mock.calls.find(
    ([action]) => action === 'contacts/update'
  );
  expect(updateCall).toBeDefined();
  return updateCall[1];
};

describe('ContactManageView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.dispatch.mockResolvedValue(undefined);
  });

  it('sends exactly { id, blocked } when blocking a contact', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper
      .findComponent({ name: 'ContactsDetailsLayout' })
      .vm.$emit('toggleBlock', false);
    await flushPromises();

    expect(emittedUpdatePayload()).toEqual({ id: 42, blocked: true });
  });

  it('sends exactly { id, blocked } when unblocking a contact', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper
      .findComponent({ name: 'ContactsDetailsLayout' })
      .vm.$emit('toggleBlock', true);
    await flushPromises();

    expect(emittedUpdatePayload()).toEqual({ id: 42, blocked: false });
  });

  it('shows the error alert when the block toggle update fails', async () => {
    mocks.dispatch.mockImplementation(action =>
      action === 'contacts/update'
        ? Promise.reject(new Error('update failed'))
        : Promise.resolve(undefined)
    );

    const wrapper = mountComponent();
    await flushPromises();

    wrapper
      .findComponent({ name: 'ContactsDetailsLayout' })
      .vm.$emit('toggleBlock', true);
    await flushPromises();

    expect(mocks.useAlert).toHaveBeenCalledWith(
      'CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_ERROR_MESSAGE'
    );
  });
});
