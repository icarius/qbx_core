import { useEffect, useState } from 'react'
import { CharacterList } from './components/CharacterList'
import { CharacterDetail } from './components/CharacterDetail'
import { CreateCharacterForm } from './components/CreateCharacterForm'
import { useNuiEvent, isEnvBrowser } from './nui'
import * as api from './api'
import type { OpenMulticharData } from './types'
import './components/Multichar.css'

type View = { type: 'list' } | { type: 'detail'; index: number } | { type: 'create'; index: number }

function App() {
  const [data, setData] = useState<OpenMulticharData | null>(null)
  const [view, setView] = useState<View>({ type: 'list' })

  useNuiEvent<OpenMulticharData>('openMultichar', (payload) => {
    setData(payload)
    setView({ type: 'list' })
  })

  useEffect(() => {
    if (isEnvBrowser()) {
      import('./mock').then((m) => m.mockBoot())
    }
  }, [])

  if (!data) return null

  function selectSlot(index: number) {
    const character = data!.characters[index]
    api.previewCharacter(character?.citizenid)
    setView(character ? { type: 'detail', index } : { type: 'create', index })
  }

  function backToList() {
    setView({ type: 'list' })
  }

  return (
    <div className="multichar-panel">
      <div className="multichar-head">
        <h2>{data.locale.multicharTitle}</h2>
        <span className="multichar-count">
          {data.characters.filter(Boolean).length}/{data.config.amount}
        </span>
      </div>

      {view.type === 'list' && <CharacterList characters={data.characters} locale={data.locale} onSelect={selectSlot} />}

      {view.type === 'detail' &&
        (() => {
          const character = data.characters[view.index]
          if (!character) return null
          return (
            <CharacterDetail
              character={character}
              locale={data.locale}
              enableDeleteButton={data.config.enableDeleteButton}
              onBack={backToList}
              onDeleted={() => {
                const characters = [...data.characters]
                characters[view.index] = null
                setData({ ...data, characters })
                setView({ type: 'list' })
              }}
            />
          )
        })()}

      {view.type === 'create' && (
        <CreateCharacterForm
          cid={view.index + 1}
          config={data.config}
          locale={data.locale}
          onBack={backToList}
          onCreated={() => {
            // The server-side flow now fades the screen out and spawns the player — nothing
            // left for this panel to do. Left mounted (rather than unmounting) since the
            // screen fade covers the transition; client/character.lua hides NUI focus itself.
          }}
        />
      )}
    </div>
  )
}

export default App
