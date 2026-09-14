import { useEffect } from 'react'

export function isEnvBrowser(): boolean {
  return !(window as any).invokeNative
}

const resourceName = (window as any).GetParentResourceName?.() ?? 'qbx_core'

export async function fetchNui<T = any>(eventName: string, data?: unknown): Promise<T> {
  if (isEnvBrowser()) {
    return mockFetchNui(eventName, data) as Promise<T>
  }

  const resp = await fetch(`https://${resourceName}/${eventName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data ?? {}),
  })

  return resp.json()
}

export function useNuiEvent<T = any>(action: string, handler: (data: T) => void) {
  useEffect(() => {
    const listener = (event: MessageEvent) => {
      const { action: msgAction, data } = event.data ?? {}
      if (msgAction === action) handler(data)
    }
    window.addEventListener('message', listener)
    return () => window.removeEventListener('message', listener)
  }, [action, handler])
}

// Dev-only stand-in so the panel is clickable outside the game (no game client to answer
// the fetch). Never bundled behavior difference in-game: isEnvBrowser() is false there.
async function mockFetchNui(eventName: string, data?: unknown): Promise<any> {
  const { mockNuiCallback } = await import('./mock')
  return mockNuiCallback(eventName, data)
}
