import { useState } from 'react'
import { useAdminGrant, useAdminRevoke, useAdminUsers, usePlans } from '../lib/queries'
import { useUserStore } from '../lib/userStore'
import { ApiError } from '../lib/api'
import type { Membership } from '../lib/types'

const formatDate = (iso: string) =>
  new Date(iso).toLocaleDateString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit' })

export function AdminPage() {
  const currentUserId = useUserStore((s) => s.currentUserId)
  const usersQ = useAdminUsers()
  const plansQ = usePlans()
  const grant = useAdminGrant()
  const revoke = useAdminRevoke()
  const [selectedPlanByUser, setSelectedPlanByUser] = useState<Record<number, number>>({})
  const [durationByUser, setDurationByUser] = useState<Record<number, string>>({})

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
    <div>
      <div className="section-header">
        <h1>유저 관리</h1>
        <span className="muted">{usersQ.data?.length ?? 0}명</span>
      </div>

      {usersQ.isLoading && <p className="muted">불러오는 중…</p>}
      {usersQ.data?.map((user) => {
        const planId = selectedPlanByUser[user.id] ?? plansQ.data?.[0]?.id ?? 0
        const duration = durationByUser[user.id] ?? ''
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
              {user.memberships.map((m: Membership) => (
                <div key={m.id} className="membership-row">
                  <div>
                    <div className="name">{m.plan.name}</div>
                    <div className="muted" style={{ marginTop: 2 }}>
                      {m.source === 'admin_grant' ? '관리자 부여' : '결제'} ·{' '}
                      {formatDate(m.started_at)} → {formatDate(m.expires_at)}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                    <span className={`badge ${m.state}`}>{m.state}</span>
                    {m.state === 'active' && (
                      <button
                        className="btn danger"
                        onClick={() => revoke.mutate(m.id)}
                        disabled={revoke.isPending}
                      >
                        회수
                      </button>
                    )}
                  </div>
                </div>
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
                    {p.name} ({p.duration_days}일)
                  </option>
                ))}
              </select>
              <input
                type="number"
                placeholder="기간 직접 입력 (일)"
                value={duration}
                onChange={(e) =>
                  setDurationByUser((s) => ({ ...s, [user.id]: e.target.value }))
                }
                style={{ width: 180 }}
              />
              <button
                className="btn primary"
                disabled={grant.isPending || !planId}
                onClick={() =>
                  grant.mutate({
                    userId: user.id,
                    planId,
                    durationDays: duration ? Number(duration) : undefined,
                  })
                }
              >
                멤버십 부여
              </button>
            </div>
          </div>
        )
      })}
    </div>
  )
}
