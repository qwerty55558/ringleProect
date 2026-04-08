// Top navigation bar. Just brand + nav links — the account picker and
// other dev affordances live in the floating DevPanel so the header
// stays clean for the recruiter screencap.

import { NavLink } from 'react-router-dom'
import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ApiError, apiFetch } from '../lib/api'
import { useUserStore } from '../lib/userStore'

export function TopBar() {
  const currentUserId = useUserStore((s) => s.currentUserId)
  const setCurrentUserId = useUserStore((s) => s.setCurrentUserId)
  const setRoster = useUserStore((s) => s.setRoster)

  // Refresh the cached roster whenever the active account changes — this
  // is what keeps the DevPanel dropdown listing every account, even after
  // we switch to a non-admin learner.
  useQuery({
    queryKey: ['topbar-users', currentUserId],
    enabled: currentUserId !== null,
    queryFn: async () => {
      try {
        const users = await apiFetch<Array<{ id: number; name: string; role: 'user' | 'admin' }>>(
          '/api/v1/admin/users',
        )
        setRoster(users.map((u) => ({ id: u.id, name: u.name, role: u.role })))
        return users
      } catch (e) {
        if (e instanceof ApiError && (e.status === 401 || e.status === 403)) return null
        throw e
      }
    },
    staleTime: 60_000,
  })

  // First load: default to user id 1 (admin from seeds).
  useEffect(() => {
    if (currentUserId === null) setCurrentUserId(1)
  }, [currentUserId, setCurrentUserId])

  return (
    <header className="topbar">
      <div className="brand">Ringle AI Tutor</div>
      <nav>
        <NavLink to="/" end>홈</NavLink>
        <NavLink to="/conversation">대화</NavLink>
        <NavLink to="/admin">관리자</NavLink>
      </nav>
      <div style={{ width: 1 }} />
    </header>
  )
}
