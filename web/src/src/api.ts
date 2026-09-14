// Mirrors client/character.lua's RegisterNUICallback handlers exactly.
import { fetchNui } from './nui'
import type { CreateCharacterForm } from './types'

// Switches the 3D preview ped — mirrors the old previewPed(citizenid) call that used to run
// on lib.showContext hover/select. `citizenid` nil previews a random ped (the "new character"
// slot).
export function previewCharacter(citizenid?: string) {
  return fetchNui<boolean>('qbx_core:multichar:preview', { citizenid })
}

export function playCharacter(citizenid: string) {
  return fetchNui<boolean>('qbx_core:multichar:play', { citizenid })
}

export function deleteCharacter(citizenid: string) {
  return fetchNui<{ success: boolean }>('qbx_core:multichar:delete', { citizenid })
}

// Profanity/format validation happens client-side in Lua (config.characters.profanityWords),
// same as the old characterDialog() flow — returns an error message to show inline instead of
// throwing, matching the old Notify()+retry loop's intent without blocking the whole panel.
export function createCharacter(cid: number, form: CreateCharacterForm) {
  return fetchNui<{ success: boolean; error?: string }>('qbx_core:multichar:create', { cid, ...form })
}

export function closeMulticharFocus() {
  return fetchNui<boolean>('qbx_core:multichar:close')
}
