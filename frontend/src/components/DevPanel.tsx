// Floating dev-tools widget. Bottom-right corner, click to expand a small
// panel with developer-only actions:
//
//   - Switch active account (the X-User-Id we forward to the API)
//   - Quick "← Admin" jump back to the seeded admin account
//   - Wipe every membership in the database
//   - Reset all browser-side state (localStorage / caches) and reload
//
// Rendered globally from App.tsx so it's available on every route.

import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../lib/api'
import { clearTtsCache } from '../lib/ttsCache'
import { useUserStore, type RosterUser } from '../lib/userStore'

const FALLBACK_ROSTER: RosterUser[] = [
  { id: 1, name: 'Ringle Admin',  role: 'admin' },
  { id: 2, name: 'Danny Learner', role: 'user' },
  { id: 3, name: 'Alex Newcomer', role: 'user' },
]

export function DevPanel() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()
  const currentUserId = useUserStore((s) => s.currentUserId)
  const setCurrentUserId = useUserStore((s) => s.setCurrentUserId)
  const roster = useUserStore((s) => s.roster)

  const effectiveRoster = roster.length > 0 ? roster : FALLBACK_ROSTER
  const adminId = effectiveRoster.find((u) => u.role === 'admin')?.id ?? 1
  const isAdmin = currentUserId === adminId

  const wipeMemberships = useMutation({
    mutationFn: () => apiFetch<{ deleted: number }>('/api/v1/admin/memberships', { method: 'DELETE' }),
    onSuccess: () => {
      queryClient.invalidateQueries()
    },
  })

  // Close on Escape
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  const resetAll = () => {
    if (!window.confirm('localStorage 전체와 모든 캐시를 초기화할까요?\n페이지가 새로고침됩니다.')) return
    try {
      window.localStorage.clear()
      window.sessionStorage.clear()
    } catch {
      /* ignore */
    }
    clearTtsCache()
    queryClient.clear()
    window.location.reload()
  }

  const handleWipeMemberships = async () => {
    if (!window.confirm('DB의 모든 멤버십을 삭제할까요?\n이 작업은 되돌릴 수 없어요.')) return
    try {
      const result = await wipeMemberships.mutateAsync()
      window.alert(`${result.deleted}개의 멤버십을 삭제했어요.`)
    } catch (e) {
      window.alert(`삭제 실패: ${(e as Error).message}\n관리자 계정으로 전환 후 다시 시도해보세요.`)
    }
  }

  return (
    <div className="dev-panel-root">
      <div className={`dev-panel-popover ${open ? 'open' : ''}`} role="dialog" aria-hidden={!open}>
        <div className="dev-panel-header">
          <span>Dev Tools</span>
          <button
            type="button"
            className="dev-panel-close"
            onClick={() => setOpen(false)}
            aria-label="Close"
          >
            ×
          </button>
        </div>

        <div className="dev-panel-section">
          <div className="dev-panel-label">현재 계정 ID</div>
          <div className="dev-panel-value">{currentUserId ?? '—'}</div>
        </div>

        <div className="dev-panel-field">
          <label className="dev-panel-label" htmlFor="dev-user-select">
            계정 전환
          </label>
          <div style={{ display: 'flex', gap: 8 }}>
            <select
              id="dev-user-select"
              className="dev-panel-select"
              value={currentUserId ?? ''}
              onChange={(e) => setCurrentUserId(Number(e.target.value))}
            >
              {effectiveRoster.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.name} ({u.role})
                </option>
              ))}
            </select>
            {!isAdmin && (
              <button
                type="button"
                className="dev-panel-action small"
                onClick={() => setCurrentUserId(adminId)}
                title="관리자 계정으로 복귀"
              >
                ← Admin
              </button>
            )}
          </div>
        </div>

        <div className="dev-panel-divider" />

        <button
          type="button"
          className="dev-panel-action danger"
          onClick={handleWipeMemberships}
          disabled={wipeMemberships.isPending}
        >
          {wipeMemberships.isPending ? '삭제 중…' : '모든 멤버십 삭제'}
        </button>
        <button type="button" className="dev-panel-action danger" onClick={resetAll}>
          모든 로컬 데이터 초기화
        </button>
        <p className="dev-panel-hint">
          멤버십 삭제는 DB의 <code>memberships</code> 테이블을 비웁니다 · 로컬 초기화는 localStorage /
          react-query / TTS 캐시를 비우고 새로고침합니다.
        </p>
      </div>

      <button
        type="button"
        className={`dev-panel-fab ${open ? 'open' : ''}`}
        onClick={() => setOpen((v) => !v)}
        aria-label="Open developer panel"
        title="Dev tools"
      >
        <WrenchIcon />
      </button>
    </div>
  )
}

function WrenchIcon() {
  return (
    <svg
      width="22"
      height="22"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M14.7 6.3a4 4 0 0 0-5.4 5.4l-6 6a1.4 1.4 0 0 0 2 2l6-6a4 4 0 0 0 5.4-5.4l-2.5 2.5-2-2 2.5-2.5z" />
    </svg>
  )
}
