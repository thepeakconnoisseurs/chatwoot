<script>
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import countries from 'shared/constants/countries.js';
import { isPhoneNumberValid } from 'shared/helpers/Validators';
import parsePhoneNumber from 'libphonenumber-js';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

export default {
  components: {
    NextButton,
    Avatar,
    ComboBox,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    inProgress: {
      type: Boolean,
      default: false,
    },
    onSubmit: {
      type: Function,
      default: () => {},
    },
  },
  emits: ['cancel', 'success'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      countries: countries,
      companyName: '',
      description: '',
      email: '',
      name: '',
      phoneNumber: '',
      originalContact: null,
      seedSnapshot: {},
      activeDialCode: '',
      avatarFile: null,
      avatarUrl: '',
      country: {
        id: '',
        name: '',
      },
      city: '',
      socialProfileUserNames: {
        facebook: '',
        twitter: '',
        linkedin: '',
        github: '',
        telegram: '',
      },
      socialProfileKeys: [
        { key: 'facebook', prefixURL: 'https://facebook.com/' },
        { key: 'twitter', prefixURL: 'https://twitter.com/' },
        { key: 'linkedin', prefixURL: 'https://linkedin.com/' },
        { key: 'github', prefixURL: 'https://github.com/' },
        { key: 'telegram', prefixURL: 'https://t.me/' },
        { key: 'tiktok', prefixURL: 'https://tiktok.com/@' },
      ],
    };
  },
  validations: {
    name: {
      required,
    },
    description: {},
    email: {
      email,
    },
    companyName: {},
    phoneNumber: {},
    bio: {},
  },
  computed: {
    parsePhoneNumber() {
      return parsePhoneNumber(this.phoneNumber);
    },
    isPhoneNumberNotValid() {
      if (this.phoneNumber !== '') {
        return (
          !isPhoneNumberValid(this.phoneNumber, this.activeDialCode) ||
          (this.phoneNumber !== '' ? this.activeDialCode === '' : false)
        );
      }
      return false;
    },
    phoneNumberError() {
      if (this.activeDialCode === '') {
        return this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DIAL_CODE_ERROR');
      }
      if (!isPhoneNumberValid(this.phoneNumber, this.activeDialCode)) {
        return this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.ERROR');
      }
      return '';
    },
    setPhoneNumber() {
      if (this.parsePhoneNumber && this.parsePhoneNumber.countryCallingCode) {
        return this.phoneNumber;
      }
      if (this.phoneNumber === '' && this.activeDialCode !== '') {
        return '';
      }
      return this.activeDialCode
        ? `${this.activeDialCode}${this.phoneNumber}`
        : '';
    },
  },
  watch: {
    'contact.id'() {
      this.fetchContact();
    },
  },
  async mounted() {
    await this.fetchContact();
  },
  methods: {
    onCancel() {
      this.$emit('cancel');
    },
    onSuccess() {
      this.$emit('success');
    },
    countryNameWithCode({ name, id }) {
      if (!id) return name;
      if (!name && !id) return '';
      return `${name} (${id})`;
    },
    onCountryChange(value) {
      const selected = this.countries.find(c => c.id === value);
      this.country = selected
        ? { id: selected.id, name: selected.name }
        : { id: '', name: '' };
    },
    // Fetch a fresh copy from `contacts/show` when the edit form opens (and
    // whenever the underlying contact changes) so the fields are seeded with
    // the unmasked values (role-aware server response) instead of a
    // possibly-masked store copy picked up from websockets.
    async fetchContact() {
      if (!this.contact.id) {
        this.setContactObject();
        this.setDialCode();
        return;
      }
      try {
        const freshContact = await this.$store.dispatch('contacts/show', {
          id: this.contact.id,
        });
        this.originalContact = freshContact;
        this.setContactObject(freshContact);
        this.setDialCode();
      } catch (error) {
        useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        this.onCancel();
      }
    },
    setDialCode() {
      if (
        this.phoneNumber !== '' &&
        this.parsePhoneNumber &&
        this.parsePhoneNumber.countryCallingCode
      ) {
        const dialCode = this.parsePhoneNumber.countryCallingCode;
        this.activeDialCode = `+${dialCode}`;
      }
    },
    // A field is pristine while it is still empty or unchanged since the last
    // seed, so a late fresh fetch never overwrites what the user already typed.
    isPristineField(field) {
      return !this[field] || this[field] === this.seedSnapshot[field];
    },
    setContactObject(contact = this.contact) {
      const {
        email: emailAddress,
        phone_number: phoneNumber,
        name,
        thumbnail,
      } = contact;
      const additionalAttributes = contact.additional_attributes || {};

      const fields = {
        name: name || '',
        email: emailAddress || '',
        phoneNumber: phoneNumber || '',
        companyName: additionalAttributes.company_name || '',
        city: additionalAttributes.city || '',
        description: additionalAttributes.description || '',
        avatarUrl: thumbnail || '',
      };
      Object.entries(fields).forEach(([field, value]) => {
        if (this.isPristineField(field)) this[field] = value;
      });

      if (
        this.country.id === '' ||
        this.country.id === this.seedSnapshot.country?.id
      ) {
        this.country = {
          id: additionalAttributes.country_code || '',
          name:
            additionalAttributes.country ||
            this.$t('CONTACT_FORM.FORM.COUNTRY.SELECT_COUNTRY'),
        };
      }

      const {
        social_profiles: socialProfiles = {},
        screen_name: twitterScreenName,
        social_telegram_user_name: telegramUserName,
      } = additionalAttributes;
      const socials = {
        twitter: socialProfiles.twitter || twitterScreenName || '',
        facebook: socialProfiles.facebook || '',
        linkedin: socialProfiles.linkedin || '',
        github: socialProfiles.github || '',
        telegram: socialProfiles.telegram || telegramUserName || '',
        instagram: socialProfiles.instagram || '',
        tiktok: socialProfiles.tiktok || '',
      };
      Object.entries(socials).forEach(([key, value]) => {
        if (
          !this.socialProfileUserNames[key] ||
          this.socialProfileUserNames[key] === this.seedSnapshot.socials?.[key]
        ) {
          this.socialProfileUserNames[key] = value;
        }
      });

      this.seedSnapshot = {
        ...fields,
        country: { ...this.country },
        socials: { ...this.socialProfileUserNames },
      };
    },
    getContactObject() {
      if (this.country === null) {
        this.country = {
          id: '',
          name: '',
        };
      }
      const contactObject = { id: this.contact.id };
      const original = this.originalContact;

      // The fresh fetch has not landed yet: send only the basic fields the user
      // explicitly typed and never a padded additional_attributes object.
      if (!original) {
        if (this.name) contactObject.name = this.name;
        if (this.email) contactObject.email = this.email;
        if (this.phoneNumber) {
          contactObject.phone_number = this.setPhoneNumber;
        }
        if (this.avatarFile) {
          contactObject.avatar = this.avatarFile;
          contactObject.isFormData = true;
        }
        return contactObject;
      }

      // Only send fields that actually changed compared to the fresh copy
      // fetched on edit-open, so masked display values can never be written back.
      const originalAttributes = original.additional_attributes || {};
      if (this.name !== (original.name || '')) {
        contactObject.name = this.name;
      }
      if (this.email !== (original.email || '')) {
        contactObject.email = this.email;
      }
      if (this.phoneNumber !== (original.phone_number || '')) {
        contactObject.phone_number = this.setPhoneNumber;
      }

      // Overlay only the attribute keys the form actually holds a value for
      // (or that already existed), so an untouched save produces no diff.
      const additionalAttributes = { ...originalAttributes };
      const selectedCountry =
        this.country.name ===
        this.$t('CONTACT_FORM.FORM.COUNTRY.SELECT_COUNTRY')
          ? ''
          : this.country.name;
      [
        ['description', this.description],
        ['company_name', this.companyName],
        ['country_code', this.country.id],
        ['country', selectedCountry],
        ['city', this.city],
      ].forEach(([key, value]) => {
        if (
          value ||
          Object.prototype.hasOwnProperty.call(originalAttributes, key)
        ) {
          additionalAttributes[key] = value;
        }
      });

      const originalSocials = originalAttributes.social_profiles || {};
      const socials = { ...originalSocials };
      Object.entries(this.socialProfileUserNames).forEach(([key, value]) => {
        if (
          value ||
          Object.prototype.hasOwnProperty.call(originalSocials, key)
        ) {
          socials[key] = value;
        }
      });
      if (JSON.stringify(socials) !== JSON.stringify(originalSocials)) {
        additionalAttributes.social_profiles = socials;
      }

      if (
        JSON.stringify(additionalAttributes) !==
        JSON.stringify(originalAttributes)
      ) {
        contactObject.additional_attributes = additionalAttributes;
      }

      if (this.avatarFile) {
        contactObject.avatar = this.avatarFile;
        contactObject.isFormData = true;
      }
      return contactObject;
    },
    setPhoneCode(code) {
      if (this.phoneNumber !== '' && this.parsePhoneNumber) {
        const dialCode = this.parsePhoneNumber.countryCallingCode;
        if (dialCode === code) {
          return;
        }
        this.activeDialCode = `+${dialCode}`;
        const newPhoneNumber = this.phoneNumber.replace(
          `+${dialCode}`,
          `${code}`
        );
        this.phoneNumber = newPhoneNumber;
      } else {
        this.activeDialCode = code;
      }
    },
    async handleSubmit() {
      this.v$.$touch();
      if (this.v$.$invalid || this.isPhoneNumberNotValid) {
        return;
      }
      try {
        await this.onSubmit(this.getContactObject());
        this.onSuccess();
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          if (error.data.includes('email')) {
            useAlert(this.$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
          } else if (error.data.includes('phone_number')) {
            useAlert(this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
          }
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    },
    handleImageUpload({ file, url }) {
      this.avatarFile = file;
      this.avatarUrl = url;
    },
    async handleAvatarDelete() {
      try {
        if (this.contact && this.contact.id) {
          await this.$store.dispatch('contacts/deleteAvatar', this.contact.id);
          useAlert(this.$t('CONTACT_FORM.DELETE_AVATAR.API.SUCCESS_MESSAGE'));
        }
        this.avatarFile = null;
        this.avatarUrl = '';
        this.activeDialCode = '';
      } catch (error) {
        useAlert(
          error.message
            ? error.message
            : this.$t('CONTACT_FORM.DELETE_AVATAR.API.ERROR_MESSAGE')
        );
      }
    },
  },
};
</script>

<template>
  <form
    class="w-full px-8 pt-6 pb-8 contact--form"
    @submit.prevent="handleSubmit"
  >
    <div class="flex flex-col mb-4 items-start gap-1 w-full">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ $t('CONTACT_FORM.FORM.AVATAR.LABEL') }}
      </label>
      <Avatar
        :src="avatarUrl"
        :size="72"
        :name="contact.name"
        allow-upload
        rounded-full
        @upload="handleImageUpload"
        @delete="handleAvatarDelete"
      />
    </div>
    <div>
      <div class="w-full">
        <label :class="{ error: v$.name.$error }">
          {{ $t('CONTACT_FORM.FORM.NAME.LABEL') }}
          <input
            v-model="name"
            type="text"
            :placeholder="$t('CONTACT_FORM.FORM.NAME.PLACEHOLDER')"
            @input="v$.name.$touch"
          />
        </label>

        <label :class="{ error: v$.email.$error }">
          {{ $t('CONTACT_FORM.FORM.EMAIL_ADDRESS.LABEL') }}
          <input
            v-model="email"
            type="text"
            :placeholder="$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.PLACEHOLDER')"
            @input="v$.email.$touch"
          />
          <span v-if="v$.email.$error" class="message">
            {{ $t('CONTACT_FORM.FORM.EMAIL_ADDRESS.ERROR') }}
          </span>
        </label>
      </div>
    </div>
    <div class="w-full">
      <label :class="{ error: v$.description.$error }">
        {{ $t('CONTACT_FORM.FORM.BIO.LABEL') }}
        <textarea
          v-model="description"
          type="text"
          :placeholder="$t('CONTACT_FORM.FORM.BIO.PLACEHOLDER')"
          @input="v$.description.$touch"
        />
      </label>
    </div>
    <div>
      <div class="w-full">
        <label
          :class="{
            error: isPhoneNumberNotValid,
          }"
        >
          {{ $t('CONTACT_FORM.FORM.PHONE_NUMBER.LABEL') }}
          <woot-phone-input
            v-model="phoneNumber"
            :value="phoneNumber"
            :error="isPhoneNumberNotValid"
            :placeholder="$t('CONTACT_FORM.FORM.PHONE_NUMBER.PLACEHOLDER')"
            @blur="v$.phoneNumber.$touch"
            @set-code="setPhoneCode"
          />
          <span v-if="isPhoneNumberNotValid" class="message">
            {{ phoneNumberError }}
          </span>
        </label>
        <div
          v-if="isPhoneNumberNotValid || !phoneNumber"
          class="relative mx-0 mt-0 mb-2.5 p-2 rounded-md text-sm border border-solid border-n-amber-5 text-n-amber-12 bg-n-amber-3"
        >
          {{ $t('CONTACT_FORM.FORM.PHONE_NUMBER.HELP') }}
        </div>
      </div>
    </div>
    <woot-input
      v-model="companyName"
      class="w-full"
      :label="$t('CONTACT_FORM.FORM.COMPANY_NAME.LABEL')"
      :placeholder="$t('CONTACT_FORM.FORM.COMPANY_NAME.PLACEHOLDER')"
    />
    <div class="w-full mb-4">
      <label>
        {{ $t('CONTACT_FORM.FORM.COUNTRY.LABEL') }}
      </label>
      <ComboBox
        :model-value="country.id"
        :options="
          countries.map(c => ({
            value: c.id,
            label: countryNameWithCode(c),
          }))
        "
        class="[&>div>button]:!bg-n-alpha-black2"
        :placeholder="$t('CONTACT_FORM.FORM.COUNTRY.PLACEHOLDER')"
        :search-placeholder="$t('CONTACT_FORM.FORM.COUNTRY.SELECT_PLACEHOLDER')"
        @update:model-value="onCountryChange"
      />
    </div>
    <woot-input
      v-model="city"
      class="w-full"
      :label="$t('CONTACT_FORM.FORM.CITY.LABEL')"
      :placeholder="$t('CONTACT_FORM.FORM.CITY.PLACEHOLDER')"
    />

    <div class="w-full">
      <label>{{ $t('CONTACTS_PAGE.LIST.TABLE_HEADER.SOCIAL_PROFILES') }}</label>
      <div
        v-for="socialProfile in socialProfileKeys"
        :key="socialProfile.key"
        class="flex items-stretch w-full mb-4"
      >
        <span
          class="flex items-center h-10 px-2 text-sm border-solid border-y ltr:border-l rtl:border-r ltr:rounded-l-md rtl:rounded-r-md bg-n-solid-3 text-n-slate-11 border-n-weak"
        >
          {{ socialProfile.prefixURL }}
        </span>
        <input
          v-model="socialProfileUserNames[socialProfile.key]"
          class="input-group-field ltr:!rounded-l-none rtl:!rounded-r-none !mb-0"
          type="text"
        />
      </div>
    </div>
    <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
      <NextButton
        type="submit"
        :label="$t('CONTACT_FORM.FORM.SUBMIT')"
        :is-loading="inProgress"
      />
      <NextButton
        faded
        slate
        type="reset"
        :label="$t('CONTACT_FORM.FORM.CANCEL')"
        @click.prevent="onCancel"
      />
    </div>
  </form>
</template>
