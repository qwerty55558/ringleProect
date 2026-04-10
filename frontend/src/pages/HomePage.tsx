import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useMe, usePlans, usePurchase, useTestCards } from '../lib/queries'
import { useUserStore } from '../lib/userStore'
import type { MembershipPlan, PurchaseResponse } from '../lib/types'
import { ApiError } from '../lib/api'
import { MembershipRow } from '../components/MembershipRow'
import { PaymentModal } from '../components/PaymentModal'
import { FEATURE_LABELS, formatFeatures, formatPriceKrw } from '../lib/format'

export function HomePage() {
  const currentUserId = useUserStore((s) => s.currentUserId)
  // The dev panel still owns the "preferred card" so power users can
  // change cards once and have it stick across modal opens; the modal
  // also lets you override per-purchase.
  const selectedCardToken = useUserStore((s) => s.selectedCardToken)
  const me = useMe()
  const plans = usePlans()
  const purchase = usePurchase()
  const testCards = useTestCards()
  const [checkoutPlan, setCheckoutPlan] = useState<MembershipPlan | null>(null)
  // After a successful purchase the modal stays open and flips to a
  // receipt view; we hold the response here until the user dismisses.
  const [receipt, setReceipt] = useState<PurchaseResponse | null>(null)

  const closeCheckout = () => {
    if (purchase.isPending) return
    setCheckoutPlan(null)
    setReceipt(null)
    purchase.reset()
  }

  const confirmCheckout = (cardToken: string) => {
    if (!checkoutPlan) return
    purchase.mutate(
      { planId: checkoutPlan.id, cardToken },
      {
        onSuccess: (data) => {
          setReceipt(data)
        },
      },
    )
  }

  if (currentUserId === null) {
    return <div className="empty-state">상단에서 계정을 선택해주세요.</div>
  }

  const hasTalk = me.data?.features.includes('talk') ?? false
  // Split memberships into "active right now" vs "anything else
  // (expired / revoked)". The home card shows the first list; the
  // second is just a counter that links to /history.
  const allMemberships = me.data?.memberships ?? []
  const activeMemberships = allMemberships.filter((m) => m.state === 'active')
  const historyCount = allMemberships.length - activeMemberships.length

  return (
    <div className="page-enter">
      <section className="hero">
        <div>
          <h1>안녕하세요, {me.data?.user.name ?? '...'} 님 👋</h1>
          <p>
            {me.data?.features.length
              ? `사용 가능한 기능: ${formatFeatures(me.data.features)}`
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
          <span className="muted">
            {(me.data?.memberships ?? []).filter((m) => m.state === 'active').length}개 활성
          </span>
        </div>
        {me.isLoading && <p className="muted">불러오는 중…</p>}
        {me.data && activeMemberships.length === 0 ? (
          <p className="empty-state">활성 멤버십이 없어요. 아래 플랜에서 골라보세요.</p>
        ) : (
          <div className="membership-list">
            {activeMemberships.map((m, i) => (
              <div key={m.id} className="stagger-item" style={{ '--i': i } as React.CSSProperties}>
                <MembershipRow membership={m} />
              </div>
            ))}
          </div>
        )}
        {historyCount > 0 && (
          <div className="card-footer">
            <Link to="/history" className="muted-link">
              지난 멤버십 {historyCount}건 보기 →
            </Link>
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
            <div key={plan.id} className="stagger-item" style={{ '--i': idx } as React.CSSProperties}>
              <PlanCard
                plan={plan}
                featured={idx === plans.data!.length - 1}
                busy={purchase.isPending && checkoutPlan?.id === plan.id}
                onBuy={() => {
                  purchase.reset()
                  setCheckoutPlan(plan)
                }}
              />
            </div>
          ))}
        </div>
        {/* Inline error stays for the case where the modal already
            closed but the toast-style banner is still useful (e.g.
            background retry). The in-modal error is the primary path. */}
        {purchase.error && !checkoutPlan && (
          <p className="error-banner error-banner--standalone">{purchaseErrorMessage(purchase.error)}</p>
        )}
      </section>

      {checkoutPlan && (
        <PaymentModal
          plan={checkoutPlan}
          card={
            (testCards.data ?? []).find((c) => c.token === selectedCardToken) ??
            (testCards.data ?? [])[0] ??
            null
          }
          busy={purchase.isPending}
          errorMessage={purchase.error ? purchaseErrorMessage(purchase.error) : null}
          receipt={receipt}
          onConfirm={confirmCheckout}
          onClose={closeCheckout}
        />
      )}
    </div>
  )
}

function purchaseErrorMessage(err: unknown): string {
  if (err instanceof ApiError) {
    if (err.status === 402) {
      const body = err.body as { reason?: string } | null
      const reason = body?.reason ?? 'card_declined'
      const human: Record<string, string> = {
        card_declined: '카드가 거절되었어요. 다른 카드로 시도해주세요.',
        insufficient_funds: '한도가 초과되었어요.',
      }
      return `결제 실패: ${human[reason] ?? reason}`
    }
    if (err.status === 502) return 'PG 서버가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도해주세요.'
    return `요청 실패 (${err.status}).`
  }
  return `구매 실패: ${(err as Error).message}`
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
      <div className="price">{formatPriceKrw(plan.price_cents)}</div>
      <ul className="feature-list">
        {plan.features.map((f) => (
          <li key={f}>{FEATURE_LABELS[f] ?? f}</li>
        ))}
      </ul>
      <button className="btn primary plan-card__cta" onClick={onBuy} disabled={busy}>
        {busy ? '결제 중…' : '구매하기'}
      </button>
    </div>
  )
}
