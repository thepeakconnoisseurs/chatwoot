import { flushPromises, shallowMount } from '@vue/test-utils';
import ContactForm from './ContactForm.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  onSubmit: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
  useTrack: vi.fn(),
}));

// A possibly-masked store copy picked up from websocket events.
const maskedContact = {
  id: 42,
  name: '+62812*****',
  phone_number: '+62812*****',
  email: 'pe***@gmail.com',
  additional_attributes: {},
  thumbnail: '',
};

// What `contacts/show` returns to an authorized viewer.
const freshContact = {
  id: 42,
  name: 'Jane Doe',
  phone_number: '+6281234567890',
  email: 'peakwine@gmail.com',
  additional_attributes: {
    company_name: 'Acme',
    description: 'VIP buyer',
    country_code: 'ID',
    country: 'Indonesia',
    city: 'Jakarta',
  },
  thumbnail: '',
};

const mountComponent = () =>
  shallowMount(ContactForm, {
    props: {
      contact: maskedContact,
      onSubmit: mocks.onSubmit,
    },
    global: {
      mocks: {
        $store: { dispatch: mocks.dispatch },
      },
    },
  });

describe('ContactForm', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('fetches a fresh contact on edit-open and seeds the fields from the response', async () => {
    mocks.dispatch.mockResolvedValue(freshContact);

    const wrapper = mountComponent();
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith('contacts/show', { id: 42 });

    expect(wrapper.vm.name).toBe('Jane Doe');
    expect(wrapper.vm.email).toBe('peakwine@gmail.com');
    expect(wrapper.vm.phoneNumber).toBe('+6281234567890');
    expect(wrapper.vm.companyName).toBe('Acme');
    expect(wrapper.vm.city).toBe('Jakarta');

    // The masked store copy must never seed the form.
    expect(wrapper.vm.phoneNumber).not.toBe('+62812*****');
    expect(wrapper.vm.email).not.toBe('pe***@gmail.com');
    expect(wrapper.vm.name).not.toBe('+62812*****');
  });

  it('keeps the fetched snapshot so an untouched submit re-sends no PII fields', async () => {
    mocks.dispatch.mockResolvedValue(freshContact);

    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.handleSubmit();

    expect(mocks.onSubmit).toHaveBeenCalledTimes(1);
    const payload = mocks.onSubmit.mock.calls[0][0];
    expect(payload.id).toBe(42);
    expect(payload).not.toHaveProperty('name');
    expect(payload).not.toHaveProperty('email');
    expect(payload).not.toHaveProperty('phone_number');
    expect(payload).not.toHaveProperty('additional_attributes');
  });

  it('refetches and reseeds when the contact prop changes (conversation switch)', async () => {
    mocks.dispatch.mockResolvedValue(freshContact);
    const wrapper = mountComponent();
    await flushPromises();

    const otherContact = {
      id: 99,
      name: '+62899*****',
      phone_number: '+62899*****',
      email: 'ot***@gmail.com',
      additional_attributes: {},
      thumbnail: '',
    };
    const otherFresh = {
      id: 99,
      name: 'Other Person',
      phone_number: '+6289988776655',
      email: 'other.person@gmail.com',
      additional_attributes: {},
      thumbnail: '',
    };
    mocks.dispatch.mockResolvedValue(otherFresh);

    await wrapper.setProps({ contact: otherContact });
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenLastCalledWith('contacts/show', {
      id: 99,
    });
    expect(wrapper.vm.name).toBe('Other Person');
    expect(wrapper.vm.email).toBe('other.person@gmail.com');
    expect(wrapper.vm.phoneNumber).toBe('+6289988776655');
  });

  it('does not overwrite fields the user already typed when the fresh fetch resolves', async () => {
    let resolveFetch;
    mocks.dispatch.mockReturnValue(
      new Promise(resolve => {
        resolveFetch = resolve;
      })
    );

    const wrapper = mountComponent();
    await wrapper.setData({ name: 'Typed Name' });

    resolveFetch(freshContact);
    await flushPromises();

    expect(wrapper.vm.name).toBe('Typed Name');
    expect(wrapper.vm.email).toBe('peakwine@gmail.com');
    expect(wrapper.vm.phoneNumber).toBe('+6281234567890');
  });

  it('sends only explicitly typed basic fields when submitted before the fresh fetch resolves', async () => {
    mocks.dispatch.mockReturnValue(new Promise(() => {}));

    const wrapper = mountComponent();
    await wrapper.setData({ name: 'Typed Only' });

    await wrapper.vm.handleSubmit();

    expect(mocks.onSubmit).toHaveBeenCalledTimes(1);
    expect(mocks.onSubmit.mock.calls[0][0]).toEqual({
      id: 42,
      name: 'Typed Only',
    });
  });

  it('aborts the edit and alerts when the fresh fetch fails, without sending a PATCH', async () => {
    mocks.dispatch.mockRejectedValue(new Error('Request failed'));

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(mocks.useAlert).toHaveBeenCalled();
    expect(mocks.onSubmit).not.toHaveBeenCalled();

    // Never seeded from the masked store copy.
    expect(wrapper.vm.name).toBe('');
    expect(wrapper.vm.phoneNumber).toBe('');
  });
});
