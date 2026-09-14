import { useState } from 'react'
import type { MulticharConfig, MulticharLocale } from '../types'
import { Button } from './ui'
import * as api from '../api'
import './Multichar.css'

export function CreateCharacterForm({
  cid,
  config,
  locale,
  onBack,
  onCreated,
}: {
  cid: number
  config: MulticharConfig
  locale: MulticharLocale
  onBack: () => void
  onCreated: () => void
}) {
  const [firstname, setFirstname] = useState('')
  const [lastname, setLastname] = useState('')
  const [nationality, setNationality] = useState(config.limitNationalities ? config.nationalities[0] ?? '' : '')
  const [gender, setGender] = useState(0)
  const [birthdate, setBirthdate] = useState(config.dateMax ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const canSubmit = firstname.trim() && lastname.trim() && nationality.trim() && birthdate

  async function handleSubmit() {
    setBusy(true)
    setError(null)
    try {
      const { success, error: err } = await api.createCharacter(cid, {
        firstname: firstname.trim(),
        lastname: lastname.trim(),
        nationality: nationality.trim(),
        gender,
        birthdate,
      })
      if (success) onCreated()
      else setError(err ?? locale.noMatchCharacterRegistration)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="char-create">
      <button className="icon-btn char-detail-back" onClick={onBack} disabled={busy} aria-label="Back">
        ←
      </button>

      <h3>{locale.characterRegistrationTitle}</h3>

      <label>
        {locale.firstName}
        <input className="text-input" value={firstname} onChange={(e) => setFirstname(e.target.value)} maxLength={50} />
      </label>

      <label>
        {locale.lastName}
        <input className="text-input" value={lastname} onChange={(e) => setLastname(e.target.value)} maxLength={50} />
      </label>

      <label>
        {locale.nationality}
        {config.limitNationalities ? (
          <select className="text-input" value={nationality} onChange={(e) => setNationality(e.target.value)}>
            {config.nationalities.map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        ) : (
          <input className="text-input" value={nationality} onChange={(e) => setNationality(e.target.value)} maxLength={50} />
        )}
      </label>

      <label>
        {locale.gender}
        <select className="text-input" value={gender} onChange={(e) => setGender(Number(e.target.value))}>
          <option value={0}>{locale.charMale}</option>
          <option value={1}>{locale.charFemale}</option>
        </select>
      </label>

      <label>
        {locale.birthDate}
        {/* Native date input only understands ISO (YYYY-MM-DD) min/max/value — matches
            config.characters.dateFormat's documented default. A server using a different
            dateFormat should keep it ISO for this picker to constrain correctly. */}
        <input
          type="date"
          className="text-input"
          value={birthdate}
          min={config.dateMin}
          max={config.dateMax}
          onChange={(e) => setBirthdate(e.target.value)}
        />
      </label>

      {error && <p className="char-create-error">{error}</p>}

      <div className="char-detail-actions">
        <Button variant="primary" disabled={!canSubmit || busy} onClick={handleSubmit}>
          {busy ? '…' : 'Créer le personnage'}
        </Button>
      </div>
    </div>
  )
}
