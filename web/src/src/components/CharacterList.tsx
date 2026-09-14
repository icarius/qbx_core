import type { CharacterCard, MulticharLocale } from '../types'
import './Multichar.css'

export function CharacterList({
  characters,
  locale,
  onSelect,
}: {
  characters: (CharacterCard | null)[]
  locale: MulticharLocale
  onSelect: (index: number) => void
}) {
  return (
    <div className="char-list">
      {characters.map((character, i) => (
        <button className={`char-slot ${character ? '' : 'is-empty'}`} key={character?.citizenid ?? `empty-${i}`} onClick={() => onSelect(i)}>
          <div className="char-slot-icon" aria-hidden>
            {character ? `${character.firstname[0] ?? ''}${character.lastname[0] ?? ''}`.toUpperCase() : '+'}
          </div>
          <div className="char-slot-body">
            {character ? (
              <>
                <h4>
                  {character.firstname} {character.lastname}
                </h4>
                <span className="char-slot-sub">{character.jobLabel}</span>
              </>
            ) : (
              <h4>{locale.newCharacter.replace('%s', String(i + 1))}</h4>
            )}
          </div>
        </button>
      ))}
    </div>
  )
}
