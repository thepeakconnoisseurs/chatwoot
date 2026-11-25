import { flushPromises, shallowMount } from '@vue/test-utils';
import ContactInfo from './ContactInfo.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => true) }) };
});

vi.mock('shared/composables/useExactTimestamp', () => ({
  useExactTimestamp: () => () => 'timestamp',
}));

// A store copy an administrator may hold after a realtime event: every role gets
// the masked payload over the websocket, so a phone-like name arrives masked.
const maskedStoreCopy = {
  id: 42,
  name: '+62812*****',
  phone_number: '+62812*****',
  email: 'pe***@gmail.com',
  additional_attributes: {},
};

// What `contacts/show` returns to an authorized viewer.
const freshContact = {
  id: 42,
  name: '+6281234567890',
  phone_number: '+6281234567890',
  email: 'peakwine@gmail.com',
  additional_attributes: {},
};

const mountComponent = (contact = maskedStoreCopy) =>
  shallowMount(ContactInfo, {
    props: { contact },
    global: {
      // the inline edit focuses the stubbed InlineInput once it opens
      stubs: { InlineInput: { template: '<div />', methods: { focus() {} } } },
      mocks: {
        $route: { params: { accountId: '1' } },
        $store: {
          dispatch: mocks.dispatch,
          getters: {
            'contacts/getUIFlags': {},
            getSelectedChat: () => ({}),
            'accounts/isFeatureEnabledonAccount': () => () => false,
          },
        },
      },
    },
  });

const updateCalls = () =>
  mocks.dispatch.mock.calls
    .filter(([action]) => action === 'contacts/update')
    .map(([, payload]) => payload);

describe('ContactInfo inline name edit', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.dispatch.mockResolvedValue(freshContact);
  });

  it('seeds the inline edit from contacts/show, never from the store copy', async () => {
    const wrapper = mountComponent();

    await wrapper.vm.startEditingName();
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith('contacts/show', {
      id: 42,
    });
    expect(wrapper.vm.editName).toBe('+6281234567890');
    expect(wrapper.vm.freshName).toBe('+6281234567890');
    expect(wrapper.vm.isEditingName).toBe(true);
    // The masked store copy must never seed the field.
    expect(wrapper.vm.editName).not.toBe('+62812*****');
    expect(mocks.useAlert).not.toHaveBeenCalled();
  });

  it('enters edit mode only after the fresh contact has arrived', async () => {
    const wrapper = mountComponent();

    const pending = wrapper.vm.startEditingName();

    // Still waiting for contacts/show: nothing may be edited yet.
    expect(wrapper.vm.isEditingName).toBe(false);
    expect(wrapper.vm.editName).toBe('');

    await pending;

    expect(wrapper.vm.isEditingName).toBe(true);
  });

  it('sends no update when the name is saved unchanged', async () => {
    const wrapper = mountComponent();
    await wrapper.vm.startEditingName();

    wrapper.vm.saveNameEdit();
    await flushPromises();

    expect(wrapper.vm.isEditingName).toBe(false);
    // Saving a masked or untouched value must never reach the API.
    expect(updateCalls()).toEqual([]);
    expect(mocks.useAlert).not.toHaveBeenCalled();
  });

  it('sends only the typed name when it changed', async () => {
    const wrapper = mountComponent();
    await wrapper.vm.startEditingName();

    wrapper.vm.editName = '  Jane Doe  ';
    wrapper.vm.saveNameEdit();
    await flushPromises();

    // Exactly { id, name }: no phone, email or other store field travels along.
    expect(updateCalls()).toEqual([{ id: 42, name: 'Jane Doe' }]);
    expect(mocks.dispatch).toHaveBeenCalledWith(
      'contacts/fetchContactableInbox',
      42
    );
    expect(mocks.useAlert).toHaveBeenCalledWith('CONTACT_FORM.SUCCESS_MESSAGE');
  });

  it('never writes a blank or whitespace-only name', async () => {
    const wrapper = mountComponent();
    await wrapper.vm.startEditingName();

    wrapper.vm.editName = '   ';
    wrapper.vm.saveNameEdit();
    await flushPromises();

    expect(updateCalls()).toEqual([]);
  });

  it('aborts the edit and alerts when the fresh fetch fails', async () => {
    const wrapper = mountComponent();
    mocks.dispatch.mockRejectedValueOnce(new Error('network'));

    await wrapper.vm.startEditingName();
    await flushPromises();

    expect(wrapper.vm.isEditingName).toBe(false);
    expect(wrapper.vm.editName).toBe('');
    expect(mocks.useAlert).toHaveBeenCalledWith('CONTACT_FORM.ERROR_MESSAGE');
    // A later save must not send anything either.
    wrapper.vm.saveNameEdit();
    await flushPromises();
    expect(updateCalls()).toEqual([]);
  });

  it('does nothing without a contact id', async () => {
    const wrapper = mountComponent({ additional_attributes: {} });

    await wrapper.vm.startEditingName();
    await flushPromises();

    // (the component's own watcher still loads contactable inboxes; that is unrelated)
    expect(mocks.dispatch).not.toHaveBeenCalledWith(
      'contacts/show',
      expect.anything()
    );
    expect(updateCalls()).toEqual([]);
    expect(wrapper.vm.isEditingName).toBe(false);
  });
});
