import { useState } from 'react'
import { useAdminGrant, useAdminRevoke, useAdminUsers, usePlans } from '../lib/queries'
import { useUserStore } from '../lib/userStore'
import { ApiError } from '../lib/api'
import { MembershipRow } from '../components/MembershipRow'
import { AdminMembershipsSubscriber } from '../components/AdminMembershipsSubscriber'
import { formatPlanDuration } from '../lib/format'
import { parseAdminGrantDuration } from '../lib/validation'

type DurationUnit = 'days' | 'seconds'

export function AdminPage() {
  const currentUserId = useUserStore((s) => s.currentUserId)
  const usersQ = useAdminUsers()
  const plansQ = usePlans()
  const grant = useAdminGrant()
  const revoke = useAdminRevoke()
  const [selectedPlanByUser, setSelectedPlanByUser] = useState<Record<number, number>>({})
  const [durationByUser, setDurationByUser] = useState<Record<number, string>>({})
  const [unitByUser, setUnitByUser] = useState<Record<number, DurationUnit>>({})
  // Per-user inline validation error for the duration override field.
  // Cleared the moment the operator edits the input or switches unit.
  const [durationErrorByUser, setDurationErrorByUser] = useState<Record<number, string>>({})

  if (currentUserId === null) {
    return <div className="empty-state">상단에서 계정을 선택해주세요.</div>
  }

  if (usersQ.error) {
    const isForbidden = usersQ.error instanceof ApiError && usersQ.error.status === 403
    return (
      <div className="card">
        <h2>관리자</h2>
        <p className="error-banner">
          {isForbidden
            ? '상단에서 admin 계정으로 전환해주세요.'
            : '관리자 데이터를 불러오지 못했어요.'}
        </p>
      </div>
    )
  }

  return (
    <div className="page-enter">
      <AdminMembershipsSubscriber />
      <div className="section-header">
        <h1>유저 관리</h1>
        <span className="muted">{usersQ.data?.length ?? 0}명</span>
      </div>

      {usersQ.isLoading && <p className="muted">불러오는 중…</p>}
      {usersQ.data?.map((user) => {
        const planId = selectedPlanByUser[user.id] ?? plansQ.data?.[0]?.id ?? 0
        const duration = durationByUser[user.id] ?? ''
        const unit = unitByUser[user.id] ?? 'days'
        return (
          <div key={user.id} className="admin-user-card">
            <div className="user-head">
              <div>
                <div className="name">{user.name}</div>
                <div className="meta">
                  {user.email} · {user.role}
                </div>
              </div>
              <span className={`badge ${user.role === 'admin' ? 'active' : 'revoked'}`}>
                {user.role}
              </span>
            </div>

            <div className="membership-list">
              {user.memberships.length === 0 && (
                <p className="muted">아직 멤버십이 없어요.</p>
              )}
              {user.memberships.map((m) => (
                <MembershipRow
                  key={m.id}
                  membership={m}
                  metaVariant="source"
                  actions={
                    m.state === 'active' ? (
                      <button
                        className="btn danger"
                        onClick={() => revoke.mutate(m.id)}
                        disabled={revoke.isPending}
                      >
                        회수
                      </button>
                    ) : null
                  }
                />
              ))}
            </div>

            <div className="admin-grant-row">
              <select
                value={planId}
                onChange={(e) =>
                  setSelectedPlanByUser((s) => ({ ...s, [user.id]: Number(e.target.value) }))
                }
              >
                {plansQ.data?.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} ({formatPlanDuration(p)})
                  </option>
                ))}
              </select>
              <input
                type="number"
                className="duration-input"
                min={1}
                step={1}
                placeholder={
                  unit === 'seconds' ? '기간 직접 입력 (초)' : '기간 직접 입력 (일)'
                }
                value={duration}
                onChange={(e) => {
                  setDurationByUser((s) => ({ ...s, [user.id]: e.target.value }))
                  setDurationErrorByUser((s) => {
                    if (!s[user.id]) return s
                    const next = { ...s }
                    delete next[user.id]
                    return next
                  })
                }}
              />
              <select
                className="duration-unit"
                value={unit}
                onChange={(e) => {
                  setUnitByUser((s) => ({ ...s, [user.id]: e.target.value as DurationUnit }))
                  setDurationErrorByUser((s) => {
                    if (!s[user.id]) return s
                    const next = { ...s }
                    delete next[user.id]
                    return next
                  })
                }}
                title="기간 단위 (만료 시뮬레이션 시 '초' 사용)"
              >
                <option value="days">일</option>
                <option value="seconds">초</option>
              </select>
              <button
                className="btn primary"
                disabled={grant.isPending || !planId}
                onClick={() => {
                  const parsed = parseAdminGrantDuration(duration, unit)
                  if (!parsed.ok) {
                    setDurationErrorByUser((s) => ({ ...s, [user.id]: parsed.error }))
                    return
                  }
                  grant.mutate({
                    userId: user.id,
                    planId,
                    durationDays: unit === 'days' && parsed.value !== null ? parsed.value : undefined,
                    durationSeconds:
                      unit === 'seconds' && parsed.value !== null ? parsed.value : undefined,
                  })
                }}
              >
                멤버십 부여
              </button>
            </div>
            {durationErrorByUser[user.id] && (
              <p className="admin-grant-error" role="alert">
                {durationErrorByUser[user.id]}
              </p>
            )}
          </div>
        )
      })}
    </div>
  )
}
