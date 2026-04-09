// Admin-only SSE: subscribes to /api/v1/admin/memberships/stream and
// invalidates the React Query cache for the admin/users list whenever
// the server pushes a `changed` event. The server fires that event for
// any membership transition across the entire database — purchase,
// admin grant, revoke, wipe-all, or time-based expiry — so every open
// admin tab repaints in real time without polling.
//
// This is the global counterpart to `useMeStream`, which only watches
// the currently signed-in user. Mounted from a render-nothing wrapper
// inside <AdminPage/> so the connection only exists while the admin
// dashboard is on screen.
//
// Auth: EventSource cannot set custom request headers, so we forward
// the active user id via `?user_id=…`. The MembershipStream controller
// promotes that into the same X-User-Id pathway every other endpoint
// uses and then enforces the admin role check.

import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { queryKeys } from './queries'
import { useUserStore } from './userStore'

const BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '')

export function useAdminMembershipsStream(): void {
  const userId = useUserStore((s) => s.currentUserId)
  const qc = useQueryClient()

  useEffect(() => {
    if (userId === null) return

    const url = new URL('/api/v1/admin/memberships/stream', BASE_URL)
    url.searchParams.set('user_id', String(userId))
    const es = new EventSource(url.toString())

    console.info('[admin/memberships/stream] connecting →', url.toString())
    es.addEventListener('open', () => console.info('[admin/memberships/stream] open'))
    es.addEventListener('error', (e) => console.warn('[admin/memberships/stream] error', e))
    es.addEventListener('ready', () => console.info('[admin/memberships/stream] ready'))
    es.addEventListener('heartbeat', () => console.debug('[admin/memberships/stream] heartbeat'))

    const onChanged = () => {
      console.info('[admin/memberships/stream] changed → invalidating adminUsers')
      // Refetch the canonical /admin/users payload. The SSE frame
      // itself is intentionally content-free — the REST endpoint is
      // the single source of truth for admin serialisation.
      qc.invalidateQueries({ queryKey: queryKeys.adminUsers })
    }
    es.addEventListener('changed', onChanged)

    return () => {
      console.info('[admin/memberships/stream] closing')
      es.removeEventListener('changed', onChanged)
      es.close()
    }
  }, [userId, qc])
}
