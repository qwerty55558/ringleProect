// Mock checkout modal for the membership purchase flow.
//
// Two visual states share the same modal frame so the user perceives a
// single "checkout sheet":
//
//   1. Confirm step (no receipt yet) — renders the card the user picked
//      in the dev panel as read-only fields plus a summary textarea, and
//      waits for the confirm click.
//   2. Receipt step (receipt prop set) — replaces the form with a
//      success card showing transaction id, amount paid, and expiry,
//      mirroring how a real PG checkout flips into a "결제 완료" screen.
//
// Decline / processing errors keep the modal in the confirm step and
// render the error inline so the user can retry without re-opening.

import { useEffect, useMemo } from 'react'
import type { MembershipPlan, PurchaseResponse, TestCard } from '../lib/types'
import { formatDateKo, formatPlanDuration, formatPriceKrw } from '../lib/format'

type Props = {
  plan: MembershipPlan
  card: TestCard | null
  busy: boolean
  errorMessage: string | null
  receipt: PurchaseResponse | null
  onConfirm: (cardToken: string) => void
  onClose: () => void
}

export function PaymentModal({
  plan,
  card,
  busy,
  errorMessage,
  receipt,
  onConfirm,
  onClose,
}: Props) {
  // Pre-filled summary textarea — exact payload the modal will submit.
  const summary = useMemo(() => {
    if (!card) return ''
    return [
      `결제 요약`,
      `--------------`,
      `상품  : ${plan.name}`,
      `금액  : ${formatPriceKrw(plan.price_cents)}`,
      `기간  : ${formatPlanDuration(plan)}`,
      ``,
      `카드사 : ${card.brand}`,
      `카드번호 : ${card.number}`,
      `유효기간 : ${card.expiry}`,
      `CVC   : ${card.cvc}`,
      `소유자 : ${card.holder}`,
      `토큰  : ${card.token}`,
    ].join('\n')
  }, [card, plan])

  // Esc to dismiss; matches DevPanel's UX so the keybinding is consistent.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !busy) onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [busy, onClose])

  // Lock body scroll for the modal's lifetime so wheel/touch events
  // don't bleed through to the page underneath. Restore the previous
  // overflow value on unmount so we don't fight other modals.
  useEffect(() => {
    const previous = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = previous
    }
  }, [])

  return (
    <div
      className="payment-modal__backdrop"
      role="dialog"
      aria-modal="true"
      aria-labelledby="payment-modal-title"
      onClick={(e) => {
        if (e.target === e.currentTarget && !busy) onClose()
      }}
    >
      <div className="payment-modal">
        <div className="payment-modal__header">
          <h2 id="payment-modal-title">{receipt ? '결제 완료' : '결제 확인'}</h2>
          <button
            type="button"
            className="payment-modal__close"
            onClick={onClose}
            disabled={busy}
            aria-label="닫기"
          >
            ×
          </button>
        </div>

        {receipt ? (
          <ReceiptView plan={plan} receipt={receipt} onClose={onClose} />
        ) : (
          <ConfirmView
            plan={plan}
            card={card}
            summary={summary}
            busy={busy}
            errorMessage={errorMessage}
            onConfirm={onConfirm}
            onClose={onClose}
          />
        )}
      </div>
    </div>
  )
}

function ConfirmView({
  plan,
  card,
  summary,
  busy,
  errorMessage,
  onConfirm,
  onClose,
}: {
  plan: MembershipPlan
  card: TestCard | null
  summary: string
  busy: boolean
  errorMessage: string | null
  onConfirm: (cardToken: string) => void
  onClose: () => void
}) {
  return (
    <>
      <div className="payment-modal__plan">
          <div className="payment-modal__plan-name">{plan.name}</div>
          <div className="payment-modal__plan-meta">
            {formatPlanDuration(plan)} · {formatPriceKrw(plan.price_cents)}
          </div>
        </div>

        <div className="payment-modal__row">
          <label className="payment-modal__field payment-modal__field--grow">
            <span className="payment-modal__label">카드사</span>
            <input
              className="payment-modal__input"
              value={card ? `${card.brand} (${card.label})` : ''}
              readOnly
              aria-readonly
            />
          </label>
        </div>

        <div className="payment-modal__row">
          <label className="payment-modal__field payment-modal__field--grow">
            <span className="payment-modal__label">카드 번호</span>
            <input
              className="payment-modal__input"
              value={card?.number ?? ''}
              readOnly
              aria-readonly
            />
          </label>
        </div>

        <div className="payment-modal__row">
          <label className="payment-modal__field">
            <span className="payment-modal__label">유효기간</span>
            <input
              className="payment-modal__input"
              value={card?.expiry ?? ''}
              readOnly
              aria-readonly
            />
          </label>
          <label className="payment-modal__field">
            <span className="payment-modal__label">CVC</span>
            <input
              className="payment-modal__input"
              value={card?.cvc ?? ''}
              readOnly
              aria-readonly
            />
          </label>
          <label className="payment-modal__field payment-modal__field--grow">
            <span className="payment-modal__label">소유자</span>
            <input
              className="payment-modal__input"
              value={card?.holder ?? ''}
              readOnly
              aria-readonly
            />
          </label>
        </div>

        <label className="payment-modal__field">
          <span className="payment-modal__label">결제 요약</span>
          <textarea
            className="payment-modal__textarea"
            value={summary}
            readOnly
            aria-readonly
            rows={10}
          />
        </label>

        {errorMessage && (
          <p className="payment-modal__error" role="alert">
            {errorMessage}
          </p>
        )}

        <div className="payment-modal__actions">
          <button
            type="button"
            className="btn ghost"
            onClick={onClose}
            disabled={busy}
          >
            취소
          </button>
          <button
            type="button"
            className="btn primary"
            onClick={() => card && onConfirm(card.token)}
            disabled={busy || !card}
          >
            {busy ? '결제 중…' : '확인하고 결제'}
          </button>
        </div>
    </>
  )
}

function ReceiptView({
  plan,
  receipt,
  onClose,
}: {
  plan: MembershipPlan
  receipt: PurchaseResponse
  onClose: () => void
}) {
  return (
    <>
      <div className="payment-modal__receipt">
        <div className="payment-modal__receipt-icon" aria-hidden>
          <svg viewBox="0 0 24 24" width="44" height="44" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" />
            <path d="M8 12.5l2.5 2.5L16 9" />
          </svg>
        </div>
        <div className="payment-modal__receipt-headline">결제가 완료되었어요</div>
        <div className="payment-modal__receipt-sub">
          {plan.name} · {formatPlanDuration(plan)}
        </div>
      </div>

      <dl className="payment-modal__receipt-list">
        <div>
          <dt>결제 금액</dt>
          <dd>{formatPriceKrw(receipt.payment.amount_cents)}</dd>
        </div>
        <div>
          <dt>결제 수단</dt>
          <dd>{receipt.payment.card_brand}</dd>
        </div>
        <div>
          <dt>거래 번호</dt>
          <dd className="payment-modal__receipt-mono">{receipt.payment.pg_transaction_id}</dd>
        </div>
        <div>
          <dt>이용 만료</dt>
          <dd>{formatDateKo(receipt.membership.expires_at)}</dd>
        </div>
      </dl>

      <div className="payment-modal__actions">
        <button type="button" className="btn primary" onClick={onClose}>
          확인
        </button>
      </div>
    </>
  )
}
