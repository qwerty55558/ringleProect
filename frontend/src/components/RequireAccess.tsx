// Page-level permission guard.
//
// Wrap any route element in <RequireAccess feature="talk">…</RequireAccess>
// or <RequireAccess role="admin">…</RequireAccess> and the element will
// only render once we've fetched /me AND the caller satisfies the
// requirement. Otherwise we render a friendly explainer card with a
// link back to home.
//
// Real-time membership updates are NOT this component's job — they
// flow through the app-level <MeStreamSubscriber/> which feeds the
// React Query cache. This guard just reads `useMe()` and re-renders
// like any other consumer when the cache changes.

import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useMe } from '../lib/queries'
import { useUserStore } from '../lib/userStore'
import { LoadingScreen } from './LoadingScreen'
import type { Feature } from '../lib/types'

type Props = {
  feature?: Feature
  role?: 'admin'
  children: ReactNode
}

export function RequireAccess({ feature, role, children }: Props) {
  const currentUserId = useUserStore((s) => s.currentUserId)
  const me = useMe()

  if (currentUserId === null) {
    return (
      <div className="empty-state">
        상단에서 계정을 선택해주세요.
      </div>
    )
  }
  if (me.isLoading || !me.data) {
    return <LoadingScreen message="권한 확인 중…" />
  }

  if (role && me.data.user.role !== role) {
    return <ForbiddenCard reason="role" missing={role} />
  }
  if (feature && !me.data.features.includes(feature)) {
    return <ForbiddenCard reason="feature" missing={feature} />
  }

  return <>{children}</>
}

const FEATURE_LABEL: Record<string, string> = {
  study: 'AI 표현 학습',
  talk: 'AI 룰플레잉',
  analysis: 'AI 디스커션',
}

function ForbiddenCard({ reason, missing }: { reason: 'role' | 'feature'; missing: string }) {
  const title =
    reason === 'role'
      ? '관리자만 접근할 수 있어요'
      : `'${FEATURE_LABEL[missing] ?? missing}' 권한이 필요해요`
  const body =
    reason === 'role'
      ? '상단 dev 패널에서 admin 계정으로 전환해주세요.'
      : '해당 기능이 포함된 활성 멤버십이 있어야 사용할 수 있어요. 멤버십이 만료되었다면 새로 결제하거나 관리자에게 부여를 요청해보세요.'
  return (
    <div className="card forbidden-card">
      <h2>{title}</h2>
      <p className="muted forbidden-card__body">{body}</p>
      <div className="forbidden-card__cta">
        <Link to="/" className="btn primary">홈으로</Link>
      </div>
    </div>
  )
}
