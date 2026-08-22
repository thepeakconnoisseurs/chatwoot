import { flushPromises, shallowMount } from '@vue/test-utils';
import ContactDetails from './ContactDetails.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  useAlert: vi.fn(),
  apiShow: vi.fn(),
  getterValues: null,
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  mocks.getterValues = {
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

vi.mock('dashboard/api/contacts', () => ({
  default: { show: mocks.apiShow },
}));

// Heavy child graphs (form, dialogs, labels) are irrelevant to the behaviors
// under test; mocking their modules keeps the spec isolated.
vi.mock(
  'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue',
  () => ({
    default: {
      name: 'ContactsForm',
      props: ['contactData', 'isDetailsView'],
      template: '<div />',
    },
  })
);
vi.mock(
  'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue',
  () => ({
    default: { name: 'ConfirmContactDeleteDialog', template: '<div />' },
  })
);
vi.mock(
  'dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue',
  () => ({
    default: { name: 'ContactLabels', template: '<div />' },
  })
);
vi.mock('dashboard/components/policy.vue', () => ({
  default: { name: 'Policy', template: '<div><slot /></div>' },
}));

// A possibly-masked store copy picked up from websocket events.
const maskedContact = {
  id: 42,
  name: '+62812*****',
  email: 'pe***@gmail.com',
  phoneNumber: '+62812*****',
  additionalAttributes: { company_name: 'Acme', city: 'Jakarta' },
};

// What `contacts/show` returns to an authorized viewer (snake_case payload).
const freshPayload = {
  id: 42,
  name: 'Jane Doe',
  email: 'peakwine@gmail.com',
  phone_number: '+6281234567890',
  additional_attributes: { company_name: 'Acme', city: 'Jakarta' },
};

const mountComponent = () =>
  shallowMount(ContactDetails, {
    props: { selectedContact: maskedContact },
  });

const findUpdateButton = wrapper =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .find(
      button =>
        button.props('label') ===
        'CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON'
    );

describe('ContactDetails', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.dispatch.mockResolvedValue(undefined);
    mocks.apiShow.mockResolvedValue({ data: { payload: freshPayload } });
  });

  it('seeds the form from the fresh fetch instead of the masked store copy', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(mocks.apiShow).toHaveBeenCalledWith(42);

    const formData = wrapper
      .findComponent({ name: 'ContactsForm' })
      .props('contactData');
    expect(formData.name).toBe('Jane Doe');
    expect(formData.email).toBe('peakwine@gmail.com');
    expect(formData.phoneNumber).toBe('+6281234567890');
  });

  it('sends no update when an untouched form is saved', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const updateButton = findUpdateButton(wrapper);
    await updateButton.trigger('click');
    await flushPromises();

    expect(mocks.dispatch).not.toHaveBeenCalledWith(
      'contacts/update',
      expect.anything()
    );
  });

  it('sends exactly { id, avatar, isFormData } when the avatar is uploaded', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const avatarFile = new File(['avatar'], 'avatar.png', {
      type: 'image/png',
    });
    wrapper.findComponent({ name: 'Avatar' }).vm.$emit('upload', {
      file: avatarFile,
      url: 'blob:avatar',
    });
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith('contacts/update', {
      id: 42,
      avatar: avatarFile,
      isFormData: true,
    });
  });
});
