// Subscribes to /api/v1/me/stream (SSE) and pushes every fresh snapshot
// into the React Query cache for `queryKeys.me(userId)`. The rest of the
// app keeps reading via `useMe()` exactly as before — this hook is the
// only thing that talks to EventSource.
//
// Mounted ONCE at the App root via <MeStreamSubscriber/>. Every page
// (home, admin, study, analysis, conversation) therefore reacts to
// membership state changes the moment the server pushes them, with a
// single shared connection that survives route transitions.
//
// On user switch (currentUserId change) the effect tears down the old
// connection and opens a new one for the new user — the dependency
// array does the work, no manual reconnect logic needed.
//
// Auth: EventSource cannot set custom request headers, so we forward
// the active user id via `?user_id=…`. The MeStream controller promotes
// that into the same X-User-Id pathway every other endpoint uses.

import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { queryKeys } from './queries'
import { useUserStore } from './userStore'
import type { MeResponse } from './types'

const BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '')

export function useMeStream(): void {
  const userId = useUserStore((s) => s.currentUserId)
  const qc = useQueryClient()

  useEffect(() => {
    if (userId === null) return

    const url = new URL('/api/v1/me/stream', BASE_URL)
    url.searchParams.set('user_id', String(userId))
    const es = new EventSource(url.toString())

    // Visible diagnostics — open the browser dev tools to confirm
    // each link of the chain (open → snapshot received → cache write).
    // These are cheap and only fire on a handful of events per session.
    console.info('[me/stream] connecting →', url.toString())
    es.addEventListener('open', () => console.info('[me/stream] open'))
    es.addEventListener('error', (e) => console.warn('[me/stream] error', e))
    es.addEventListener('heartbeat', () => console.debug('[me/stream] heartbeat'))

    const onSnapshot = (ev: MessageEvent) => {
      console.info('[me/stream] snapshot ←', ev.data)
      try {
        const payload = JSON.parse(ev.data) as MeResponse
        qc.setQueryData(queryKeys.me(userId), payload)
      } catch (err) {
        console.warn('[me/stream] failed to parse snapshot', err)
      }
    }

    // The server emits typed events: `snapshot` for state changes,
    // `heartbeat` for keepalive, `error` for hard failures. We only
    // act on snapshots; the others exist purely to keep the socket
    // alive and to surface server-side abort reasons.
    es.addEventListener('snapshot', onSnapshot as EventListener)

    return () => {
      console.info('[me/stream] closing')
      es.removeEventListener('snapshot', onSnapshot as EventListener)
      es.close()
    }
  }, [userId, qc])
}
