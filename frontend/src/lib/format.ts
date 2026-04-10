// Cross-page formatting helpers and label dictionaries. Lifted out of
// HomePage so AdminPage (and any future page that renders memberships)
// can share the exact same display logic.

export const formatPriceKrw = (cents: number): string =>
  `₩${(cents / 100).toLocaleString('ko-KR')}`

export const formatDateKo = (iso: string): string =>
  new Date(iso).toLocaleDateString('ko-KR', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })

export const FEATURE_LABELS: Record<string, string> = {
  study: 'AI 표현 학습',
  talk: 'AI 룰플레잉',
  analysis: 'AI 디스커션',
}

export const formatFeatures = (features: readonly string[]): string =>
  features.map((f) => FEATURE_LABELS[f] ?? f).join(' · ')

// Plan duration label that works for both day-based and sub-day plans.
// Prefers the server-supplied `duration_label` when present (it already
// formats the right unit) so the front-end never has to guess.
export const formatPlanDuration = (plan: {
  duration_label?: string
  duration_seconds: number | null
  duration_days: number
}): string => {
  if (plan.duration_label) return `${plan.duration_label} 이용`
  if (plan.duration_seconds) return `${plan.duration_seconds}초 이용`
  return `${plan.duration_days}일 이용`
}
