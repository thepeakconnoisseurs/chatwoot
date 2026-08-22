import { flushPromises, mount } from '@vue/test-utils';
import ContactsCard from './ContactsCard.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
}));

vi.mock(
  'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue',
  () => ({
    default: {
      name: 'ContactsForm',
      props: ['contactData'],
      template: '<div />',
    },
  })
);
vi.mock(
  'dashboard/components-next/Contacts/ContactsCard/ContactDeleteSection.vue',
  () => ({
    default: { name: 'ContactDeleteSection', template: '<div />' },
  })
);

// Possibly-masked list copy passed as props.
const maskedProps = {
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
  mount(ContactsCard, {
    props: maskedProps,
    global: {
      stubs: {
        CardLayout: { template: '<div><slot /><slot name="after" /></div>' },
        Avatar: { template: '<span />' },
        Flag: { template: '<span />' },
      },
    },
  });

const findExpandButton = wrapper =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .find(button => button.props('icon') === 'i-lucide-chevron-down');

const findSaveButton = wrapper =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .find(
      button =>
        button.props('label') ===
        'CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON'
    );

describe('ContactsCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.dispatch.mockResolvedValue(freshPayload);
  });

  it('fetches a fresh contact before seeding the inline edit form', async () => {
    const wrapper = mountComponent();

    await findExpandButton(wrapper).trigger('click');
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith('contacts/show', { id: 42 });
    expect(wrapper.emitted('toggle')).toHaveLength(1);

    const formData = wrapper
      .findComponent({ name: 'ContactsForm' })
      .props('contactData');
    expect(formData.name).toBe('Jane Doe');
    expect(formData.email).toBe('peakwine@gmail.com');
    expect(formData.phoneNumber).toBe('+6281234567890');
  });

  it('does not toggle twice when the expand button is clicked rapidly', async () => {
    const wrapper = mountComponent();

    const expandButton = findExpandButton(wrapper);
    expandButton.trigger('click');
    expandButton.trigger('click');
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('toggle')).toHaveLength(1);
  });

  it('emits only { id } when an untouched form is saved', async () => {
    const wrapper = mountComponent();

    await findExpandButton(wrapper).trigger('click');
    await flushPromises();

    await findSaveButton(wrapper).trigger('click');

    expect(wrapper.emitted('updateContact')).toEqual([[{ id: 42 }]]);
  });
});
