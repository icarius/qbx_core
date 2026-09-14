import { useState } from 'react'
import type { CharacterCard, MulticharLocale } from '../types'
import { Button, Modal } from './ui'
import * as api from '../api'
import './Multichar.css'

export function CharacterDetail({
  character,
  locale,
  enableDeleteButton,
  onBack,
  onDeleted,
}: {
  character: CharacterCard
  locale: MulticharLocale
  enableDeleteButton: boolean
  onBack: () => void
  onDeleted: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState(false)

  async function handlePlay() {
    setBusy(true)
    await api.playCharacter(character.citizenid)
    // No need to reset busy — the screen fades out and this panel unmounts.
  }

  async function handleDelete() {
    setBusy(true)
    try {
      const { success } = await api.deleteCharacter(character.citizenid)
      if (success) onDeleted()
    } finally {
      setBusy(false)
      setConfirmingDelete(false)
    }
  }

  const initials = `${character.firstname[0] ?? ''}${character.lastname[0] ?? ''}`.toUpperCase()
  const hasGang = character.gangGradeName && character.gangGradeName.toLowerCase() !== 'none'

  return (
    <div className="char-detail">
      <button className="icon-btn char-detail-back" onClick={onBack} disabled={busy} aria-label="Back">
        ←
      </button>

      <div className="char-hero">
        <div className="char-hero-avatar">{initials}</div>
        <div>
          <h3>
            {character.firstname} {character.lastname}
          </h3>
          <div className="plate">{character.citizenid}</div>
        </div>
      </div>

      <div className="char-group">
        <div className="char-info-row is-money">
          <span>Cash</span>
          <strong>${character.cash.toLocaleString()}</strong>
        </div>
        <div className="char-info-row is-money">
          <span>Bank</span>
          <strong>${character.bank.toLocaleString()}</strong>
        </div>
      </div>

      <div className="char-group">
        <div className="char-info-row">
          <span>Job</span>
          <strong>
            {character.jobLabel} <span className="value-muted">— {character.jobGradeName}</span>
          </strong>
        </div>
        <div className="char-info-row">
          <span>Gang</span>
          <strong className={hasGang ? '' : 'value-muted'}>{hasGang ? `${character.gangLabel} — ${character.gangGradeName}` : 'No gang'}</strong>
        </div>
      </div>

      <div className="char-group">
        <div className="char-info-row">
          <span>{locale.gender}</span>
          <strong>{character.gender === 0 ? locale.charMale : locale.charFemale}</strong>
        </div>
        <div className="char-info-row">
          <span>{locale.birthDate}</span>
          <strong>{character.birthdate}</strong>
        </div>
        <div className="char-info-row">
          <span>{locale.nationality}</span>
          <strong>{character.nationality}</strong>
        </div>
        <div className="char-info-row">
          <span>Phone</span>
          <strong>{character.phoneNumber}</strong>
        </div>
      </div>

      <div className="char-detail-actions">
        <Button variant="primary" disabled={busy} onClick={handlePlay}>
          {locale.play}
        </Button>
        {enableDeleteButton && (
          <Button variant="danger" disabled={busy} onClick={() => setConfirmingDelete(true)}>
            {locale.deleteCharacter}
          </Button>
        )}
      </div>

      {confirmingDelete && (
        <Modal
          title={locale.deleteCharacter}
          onClose={() => setConfirmingDelete(false)}
          footer={
            <>
              <Button size="sm" onClick={() => setConfirmingDelete(false)}>
                Annuler
              </Button>
              <Button variant="danger" size="sm" disabled={busy} onClick={handleDelete}>
                {locale.deleteCharacter}
              </Button>
            </>
          }
        >
          <p>{locale.confirmDelete}</p>
        </Modal>
      )}
    </div>
  )
}
