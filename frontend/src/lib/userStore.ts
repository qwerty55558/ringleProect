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
  // Active conversation per user. We persist a map (not a single id) so
  // switching the X-User-Id picker doesn't accidentally hand someone
  // else's conversation to the new account — the talk endpoint would
  // 404 anyway, but losing it client-side is faster.
  conversationByUser: Record<number, number>
  // Currently selected PG mock card token. Lives here (instead of in
  // HomePage local state) so the DevPanel can own the picker UI while
  // the home page reads the chosen token at purchase time.
  selectedCardToken: string
  setCurrentUserId: (id: number | null) => void
  setRoster: (users: RosterUser[]) => void
  setConversationForCurrentUser: (conversationId: number | null) => void
  getConversationForCurrentUser: () => number | null
  setSelectedCardToken: (token: string) => void
}

export const useUserStore = create<State>()(
  persist(
    (set, get) => ({
      currentUserId: null,
      roster: [],
      conversationByUser: {},
      selectedCardToken: 'tok_visa',
      setCurrentUserId: (id) => set({ currentUserId: id }),
      setRoster: (users) => set({ roster: users }),
      setSelectedCardToken: (token) => set({ selectedCardToken: token }),
      setConversationForCurrentUser: (conversationId) => {
        const userId = get().currentUserId
        if (userId === null) return
        const next = { ...get().conversationByUser }
        if (conversationId === null) delete next[userId]
        else next[userId] = conversationId
        set({ conversationByUser: next })
      },
      getConversationForCurrentUser: () => {
        const userId = get().currentUserId
        return userId === null ? null : (get().conversationByUser[userId] ?? null)
      },
    }),
    { name: 'ringle.userStore' },
  ),
)
