import type { OpenMulticharData } from './types'

export async function mockNuiCallback(eventName: string, data?: any): Promise<any> {
  await new Promise((r) => setTimeout(r, 250))
  console.log('[mock]', eventName, data)

  switch (eventName) {
    case 'qbx_core:multichar:create':
      if (data.firstname === 'fail') return { success: false, error: 'Anything other than letters is not allowed.' }
      return { success: true }
    case 'qbx_core:multichar:delete':
      return { success: true }
    default:
      return true
  }
}

const mockData: OpenMulticharData = {
  characters: [
    {
      citizenid: 'ABC123XYZ',
      firstname: 'Jean',
      lastname: 'Dupont',
      gender: 0,
      birthdate: '01/01/1990',
      nationality: 'French',
      accountNumber: 'QB-12345',
      phoneNumber: '555-1234',
      cash: 500,
      bank: 15420,
      jobLabel: 'Police',
      jobGradeName: 'Sergeant',
      gangLabel: 'No Gang',
      gangGradeName: 'none',
    },
    {
      citizenid: 'DEF456UVW',
      firstname: 'Marie',
      lastname: 'Martin',
      gender: 1,
      birthdate: '15/06/1988',
      nationality: 'French',
      accountNumber: 'QB-67890',
      phoneNumber: '555-5678',
      cash: 120,
      bank: 3200,
      jobLabel: 'Civilian',
      jobGradeName: 'Freelancer',
      gangLabel: 'No Gang',
      gangGradeName: 'none',
    },
    null,
  ],
  config: {
    amount: 3,
    enableDeleteButton: true,
    limitNationalities: false,
    nationalities: ['American', 'French', 'German'],
    dateFormat: 'DD/MM/YYYY',
    dateMin: '1900-01-01',
    dateMax: '2010-01-01',
  },
  locale: {
    multicharTitle: 'Qbox Multichar',
    newCharacter: 'New Character #%s',
    charMale: 'Male',
    charFemale: 'Female',
    play: 'Play',
    playDescription: 'Play as %s',
    deleteCharacter: 'Delete Character',
    deleteCharacterDescription: 'Delete %s',
    confirmDelete: 'Are you sure you wish to delete this character?',
    characterRegistrationTitle: 'Character Registration',
    firstName: 'First Name',
    lastName: 'Last Name',
    nationality: 'Nationality',
    gender: 'Sex',
    birthDate: 'Birth Date',
    selectGender: 'Select your gender...',
    noMatchCharacterRegistration: 'Only letters are allowed, and words must start with a capital letter.',
  },
}

export function mockBoot() {
  setTimeout(() => {
    window.postMessage({ action: 'openMultichar', data: mockData }, '*')
  }, 100)
}
