// Shared zod schemas for client-side input validation. We keep them in
// one file (rather than co-located with each form) so the constraints
// stay in sync with the matching backend guards in
// `Memberships::AdminGrant` — change one place, change both.
//
// Constraint rationale (admin grant duration):
//   - The "기간 직접 입력" field on /admin lets the operator override a
//     plan's natural duration so we can demo expiry without waiting.
//   - We allow "일" (days) and "초" (seconds) modes via a sibling toggle.
//   - Hard rules: must be a positive integer, never zero, never beyond
//     100 days. Seconds mode therefore maxes out at 100 × 86400.
//
// We surface errors via `safeParse` so the form can render the message
// inline without throwing.

import { z } from 'zod'

export const MAX_GRANT_DAYS = 100
export const MAX_GRANT_SECONDS = MAX_GRANT_DAYS * 24 * 60 * 60

export const adminGrantDurationSchema = z.discriminatedUnion('unit', [
  z.object({
    unit: z.literal('days'),
    value: z
      .number({ message: '숫자를 입력해주세요.' })
      .int('정수여야 해요.')
      .positive('1일 이상이어야 해요.')
      .max(MAX_GRANT_DAYS, `${MAX_GRANT_DAYS}일을 초과할 수 없어요.`),
  }),
  z.object({
    unit: z.literal('seconds'),
    value: z
      .number({ message: '숫자를 입력해주세요.' })
      .int('정수여야 해요.')
      .positive('1초 이상이어야 해요.')
      .max(MAX_GRANT_SECONDS, `${MAX_GRANT_SECONDS}초(${MAX_GRANT_DAYS}일)를 초과할 수 없어요.`),
  }),
])

export type AdminGrantDurationInput = z.infer<typeof adminGrantDurationSchema>

// Convenience helper: parse the raw form values (string + unit) and
// return either { ok: true, value } or { ok: false, error }. Empty
// string is allowed and means "use the plan's natural duration".
export function parseAdminGrantDuration(
  raw: string,
  unit: 'days' | 'seconds',
): { ok: true; value: number | null } | { ok: false, error: string } {
  const trimmed = raw.trim()
  if (trimmed === '') return { ok: true, value: null }

  const numeric = Number(trimmed)
  if (Number.isNaN(numeric)) return { ok: false, error: '숫자를 입력해주세요.' }

  const result = adminGrantDurationSchema.safeParse({ unit, value: numeric })
  if (!result.success) {
    return { ok: false, error: result.error.issues[0]?.message ?? '입력값을 확인해주세요.' }
  }
  return { ok: true, value: result.data.value }
}
