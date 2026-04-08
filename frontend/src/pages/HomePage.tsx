import { Link } from 'react-router-dom'
import { useMe, usePlans, usePurchase } from '../lib/queries'
import { useUserStore } from '../lib/userStore'
import type { Membership, MembershipPlan } from '../lib/types'
import { ApiError } from '../lib/api'

const formatPrice = (cents: number) => `₩${(cents / 100).toLocaleString('ko-KR')}`

const formatDate = (iso: string) =>
  new Date(iso).toLocaleDateString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit' })

const FEATURE_LABELS: Record<string, string> = {
  study: 'AI 표현 학습',
  talk: 'AI 룰플레잉',
  analysis: 'AI 디스커션',
}

export function HomePage() {
  const currentUserId = useUserStore((s) => s.currentUserId)
  const me = useMe()
  const plans = usePlans()
  const purchase = usePurchase()

  if (currentUserId === null) {
    return <div className="empty-state">상단에서 계정을 선택해주세요.</div>
  }

  const hasTalk = me.data?.features.includes('talk') ?? false

  return (
    <div>
      <section className="hero">
        <div>
          <h1>안녕하세요, {me.data?.user.name ?? '...'} 님 👋</h1>
          <p>
            {me.data?.features.length
              ? `사용 가능한 기능: ${me.data.features.map((f) => FEATURE_LABELS[f] ?? f).join(' · ')}`
              : '아직 활성 멤버십이 없어요. 아래에서 시작해보세요.'}
          </p>
        </div>
        {hasTalk && (
          <Link to="/conversation" className="btn big">
            대화 시작하기 →
          </Link>
        )}
      </section>

      <section className="card">
        <div className="section-header">
          <h2>나의 멤버십</h2>
          <span className="muted">{me.data?.memberships.length ?? 0}개</span>
        </div>
        {me.isLoading && <p className="muted">불러오는 중…</p>}
        {me.data && me.data.memberships.length === 0 ? (
          <p className="empty-state">아직 멤버십이 없어요. 아래 플랜에서 골라보세요.</p>
        ) : (
          <div className="membership-list">
            {me.data?.memberships.map((m) => (
              <MembershipRow key={m.id} membership={m} />
            ))}
          </div>
        )}
      </section>

      <section>
        <div className="section-header">
          <h2>플랜</h2>
          <span className="muted">{plans.data?.length ?? 0}개 플랜</span>
        </div>
        {plans.isLoading && <p className="muted">플랜을 불러오는 중…</p>}
        <div className="plan-grid">
          {plans.data?.map((plan, idx) => (
            <PlanCard
              key={plan.id}
              plan={plan}
              featured={idx === plans.data!.length - 1}
              busy={purchase.isPending}
              onBuy={() => purchase.mutate(plan.id)}
            />
          ))}
        </div>
        {purchase.error && (
          <p className="error-banner" style={{ marginTop: 16 }}>
            {purchase.error instanceof ApiError && purchase.error.status === 402
              ? '결제가 거절되었어요. 다시 시도해주세요.'
              : `구매 실패: ${(purchase.error as Error).message}`}
          </p>
        )}
      </section>
    </div>
  )
}

function MembershipRow({ membership }: { membership: Membership }) {
  return (
    <div className="membership-row">
      <div>
        <div className="name">{membership.plan.name}</div>
        <div className="muted" style={{ marginTop: 2 }}>
          {membership.plan.features.map((f) => FEATURE_LABELS[f] ?? f).join(' · ')} ·{' '}
          {formatDate(membership.started_at)} → {formatDate(membership.expires_at)}
        </div>
      </div>
      <span className={`badge ${membership.state}`}>{membership.state}</span>
    </div>
  )
}

function PlanCard({
  plan,
  featured,
  busy,
  onBuy,
}: {
  plan: MembershipPlan
  featured: boolean
  busy: boolean
  onBuy: () => void
}) {
  return (
    <div className={`plan-card ${featured ? 'featured' : ''}`}>
      {featured && <div className="badge-popular">인기</div>}
      <h3>{plan.name}</h3>
      <div className="duration">{plan.duration_days}일 이용</div>
      <div className="price">{formatPrice(plan.price_cents)}</div>
      <ul className="feature-list">
        {plan.features.map((f) => (
          <li key={f}>{FEATURE_LABELS[f] ?? f}</li>
        ))}
      </ul>
      <button className="btn primary" onClick={onBuy} disabled={busy} style={{ marginTop: 'auto' }}>
        {busy ? '결제 중…' : '구매하기'}
      </button>
    </div>
  )
}
