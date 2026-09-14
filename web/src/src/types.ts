export interface CharacterCard {
  citizenid: string
  firstname: string
  lastname: string
  gender: number
  birthdate: string
  nationality: string
  accountNumber: string
  phoneNumber: string
  cash: number
  bank: number
  jobLabel: string
  jobGradeName: string
  gangLabel: string
  gangGradeName: string
}

export interface MulticharLocale {
  multicharTitle: string
  newCharacter: string
  charMale: string
  charFemale: string
  play: string
  playDescription: string
  deleteCharacter: string
  deleteCharacterDescription: string
  confirmDelete: string
  characterRegistrationTitle: string
  firstName: string
  lastName: string
  nationality: string
  gender: string
  birthDate: string
  selectGender: string
  noMatchCharacterRegistration: string
}

export interface MulticharConfig {
  amount: number
  enableDeleteButton: boolean
  limitNationalities: boolean
  nationalities: string[]
  dateFormat: string
  dateMin?: string
  dateMax?: string
}

export interface OpenMulticharData {
  characters: (CharacterCard | null)[]
  config: MulticharConfig
  locale: MulticharLocale
}

export interface CreateCharacterForm {
  firstname: string
  lastname: string
  nationality: string
  gender: number
  birthdate: string
}
