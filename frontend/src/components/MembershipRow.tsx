// Cross-page primitive: one row in a list of memberships. Used by both
// HomePage (a learner viewing their own memberships) and AdminPage (an
// admin viewing every learner's memberships, with a revoke action).
//
// The two call sites differ in just two ways:
//   1. Admin shows the source ("관리자 부여" vs. "결제"); home shows the
//      feature list instead.
//   2. Admin renders an action slot to the right of the badge.
// Both differences are exposed as props rather than duplicating markup.

import type { ReactNode } from 'react'
import type { Membership } from '../lib/types'
import { formatDateKo, formatFeatures } from '../lib/format'

type Props = {
  membership: Membership
  /** What to render in the meta row under the plan name. */
  metaVariant?: 'features' | 'source'
  /** Optional action(s) rendered next to the state badge. */
  actions?: ReactNode
}

export function MembershipRow({ membership, metaVariant = 'features', actions }: Props) {
  const meta =
    metaVariant === 'source'
      ? `${membership.source === 'admin_grant' ? '관리자 부여' : '결제'} · ${formatDateKo(membership.started_at)} → ${formatDateKo(membership.expires_at)}`
      : `${formatFeatures(membership.plan.features)} · ${formatDateKo(membership.started_at)} → ${formatDateKo(membership.expires_at)}`

  return (
    <div className="membership-row">
      <div>
        <div className="name">{membership.plan.name}</div>
        <div className="membership-row__meta">{meta}</div>
      </div>
      {actions ? (
        <div className="membership-row__actions">
          <span className={`badge ${membership.state}`}>{membership.state}</span>
          {actions}
        </div>
      ) : (
        <span className={`badge ${membership.state}`}>{membership.state}</span>
      )}
    </div>
  )
}
