// Top navigation bar.
//
// Tabs are rendered dynamically from /me so a learner with only the
// `study` feature sees only [홈, 학습], a learner with `talk` sees the
// 대화 tab too, and admins get the 관리자 tab. Tabs that the user can't
// access never appear at all — they aren't disabled, they're hidden,
// because the recruiter screencap should match the user's actual
// permission scope.

import { NavLink } from 'react-router-dom'
import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ApiError, apiFetch } from '../lib/api'
import { useMe } from '../lib/queries'
import { useUserStore } from '../lib/userStore'

type Tab = { to: string; label: string; end?: boolean; show: boolean }

export function TopBar() {
  const currentUserId = useUserStore((s) => s.currentUserId)
  const setCurrentUserId = useUserStore((s) => s.setCurrentUserId)
  const setRoster = useUserStore((s) => s.setRoster)
  const me = useMe()

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

  const features = me.data?.features ?? []
  const isAdmin = me.data?.user.role === 'admin'

  const tabs: Tab[] = [
    { to: '/',             label: '홈',     end: true, show: true },
    { to: '/study',        label: '학습',              show: features.includes('study') },
    { to: '/conversation', label: '대화',              show: features.includes('talk') },
    { to: '/analysis',     label: '분석',              show: features.includes('analysis') },
    { to: '/admin',        label: '관리자',            show: isAdmin },
  ]

  return (
    <header className="topbar">
      <div className="brand">Ringle AI Tutor</div>
      <nav>
        {tabs
          .filter((t) => t.show)
          .map((t) => (
            <NavLink key={t.to} to={t.to} end={t.end}>
              {t.label}
            </NavLink>
          ))}
      </nav>
      {/* Empty third slot keeps the nav visually centered between brand
          and the right edge under the topbar's space-between layout. */}
      <div className="topbar__spacer" aria-hidden />
    </header>
  )
}
