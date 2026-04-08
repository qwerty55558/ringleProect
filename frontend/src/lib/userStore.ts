// Persistent "current user" selector. Real auth is out of scope per the
// spec, so the user picks who they're acting as via the top-bar dropdown
// and we forward that as the X-User-Id header on every request.

import { create } from 'zustand'
import { persist } from 'zustand/middleware'

// Account roster the picker has seen at any point. We cache the list so the
// dropdown still shows everyone even after switching to a non-admin account
// (the admin endpoint that populates this list 403s for learners). The
// roster auto-refreshes whenever an admin call succeeds.
export type RosterUser = { id: number; name: string; role: 'user' | 'admin' }

type State = {
  currentUserId: number | null
  roster: RosterUser[]
  setCurrentUserId: (id: number | null) => void
  setRoster: (users: RosterUser[]) => void
}

export const useUserStore = create<State>()(
  persist(
    (set) => ({
      currentUserId: null,
      roster: [],
      setCurrentUserId: (id) => set({ currentUserId: id }),
      setRoster: (users) => set({ roster: users }),
    }),
    { name: 'ringle.userStore' },
  ),
)
