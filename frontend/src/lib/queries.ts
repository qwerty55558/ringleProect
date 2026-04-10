// Centralized react-query hooks. Keeping query keys in one place avoids
// stale-cache surprises and makes invalidations cheap to reason about.

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from './api'
import { useUserStore } from './userStore'
import type {
  AdminUser,
  Conversation,
  MeResponse,
  MembershipPlan,
  PurchaseResponse,
  SttFixture,
  StudyMaterial,
  StudyMaterialsResponse,
  TestCard,
} from './types'

export const queryKeys = {
  me: (id: number | null) => ['me', id] as const,
  plans: ['membershipPlans'] as const,
  adminUsers: ['admin', 'users'] as const,
  testCards: ['payments', 'testCards'] as const,
  studyMaterials: ['studyMaterials'] as const,
  studyMaterial: (id: number) => ['studyMaterial', id] as const,
  conversations: ['conversations'] as const,
}

export function useConversations() {
  return useQuery({
    queryKey: queryKeys.conversations,
    queryFn: () => apiFetch<Conversation[]>('/api/v1/conversations'),
  })
}

export function useStudyMaterials(enabled = true) {
  return useQuery({
    queryKey: queryKeys.studyMaterials,
    queryFn: () => apiFetch<StudyMaterialsResponse>('/api/v1/study_materials'),
    enabled,
  })
}

export function useStudyMaterial(id: number | null) {
  return useQuery({
    queryKey: queryKeys.studyMaterial(id ?? 0),
    queryFn: () => apiFetch<StudyMaterial>(`/api/v1/study_materials/${id}`),
    enabled: id !== null,
  })
}

export function useSttFixtures(enabled = true) {
  return useQuery({
    queryKey: ['sttFixtures'],
    queryFn: () => apiFetch<SttFixture[]>('/api/v1/stt_fixtures'),
    staleTime: Infinity,
    enabled,
  })
}

export function useGenerateStudyMaterial() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (topic: string) =>
      apiFetch<StudyMaterial>('/api/v1/study_materials/generate', {
        method: 'POST',
        body: { topic },
      }),
    retry: 2,
    retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 10000),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.studyMaterials })
      qc.invalidateQueries({ queryKey: ['me'] })
    },
  })
}

// Admin-only nuke-and-reseed for the study curriculum. Powers the
// dev panel's "커리큘럼 리셋" button. The backend wipes AI-generated
// rows, resets every user's generation counter, re-runs CurriculumSeed,
// and broadcasts via Study::Bus — every open /study tab refetches via
// the SSE channel without us having to invalidate manually.
export function useResetStudyCurriculum() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () =>
      apiFetch<{ ok: boolean; deleted_ai_rows: number; user_counters_reset: number; seeded: number }>(
        '/api/v1/admin/study_materials/reset',
        { method: 'POST' },
      ),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.studyMaterials })
      qc.invalidateQueries({ queryKey: ['me'] })
    },
  })
}

// Admin-only targeted delete for AI-generated curriculum rows only.
// Unlike useResetStudyCurriculum, this leaves the seeded rows AND the
// per-user generation counters alone — use case is "the AI pool went
// stale, scrub it without forcing every learner back to 3 fresh slots".
// Same Study::Bus broadcast → every /study tab repaints automatically.
export function useDeleteAiStudyMaterials() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () =>
      apiFetch<{ ok: boolean; deleted: number }>(
        '/api/v1/admin/study_materials/ai_generated',
        { method: 'DELETE' },
      ),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.studyMaterials })
    },
  })
}

export function useResetStudyGenerationCounters() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () =>
      apiFetch<{ ok: boolean; users_reset: number }>(
        '/api/v1/admin/study_materials/reset_generation_counters',
        { method: 'POST' },
      ),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['me'] })
    },
  })
}

export function useTestCards() {
  return useQuery({
    queryKey: queryKeys.testCards,
    queryFn: () => apiFetch<TestCard[]>('/api/v1/payments/test_cards'),
    staleTime: Infinity,
  })
}

export function useMe() {
  const userId = useUserStore((s) => s.currentUserId)
  return useQuery({
    queryKey: queryKeys.me(userId),
    queryFn: async () => {
      const data = await apiFetch<MeResponse>('/api/v1/me')
      if (data.server_time) {
        const { setServerTimeOffset } = await import('./serverTime')
        setServerTimeOffset(data.server_time)
      }
      return data
    },
    enabled: userId !== null,
    staleTime: Infinity,
  })
}

export function usePlans() {
  return useQuery({
    queryKey: queryKeys.plans,
    queryFn: () => apiFetch<MembershipPlan[]>('/api/v1/membership_plans'),
  })
}

export function useAdminUsers() {
  return useQuery({
    queryKey: queryKeys.adminUsers,
    queryFn: () => apiFetch<AdminUser[]>('/api/v1/admin/users'),
  })
}

export function usePurchase() {
  const qc = useQueryClient()
  const userId = useUserStore((s) => s.currentUserId)
  return useMutation({
    mutationFn: (vars: { planId: number; cardToken: string }) =>
      apiFetch<PurchaseResponse>('/api/v1/payments', {
        method: 'POST',
        body: {
          membership_plan_id: vars.planId,
          payment_method: { card_token: vars.cardToken },
        },
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.me(userId) })
      qc.invalidateQueries({ queryKey: queryKeys.adminUsers })
    },
  })
}

export function useAdminGrant() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (vars: {
      userId: number
      planId: number
      durationDays?: number
      durationSeconds?: number
    }) =>
      apiFetch('/api/v1/admin/memberships', {
        method: 'POST',
        body: {
          user_id: vars.userId,
          membership_plan_id: vars.planId,
          duration_days: vars.durationDays,
          duration_seconds: vars.durationSeconds,
        },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: queryKeys.adminUsers }),
  })
}

export function useAdminRevoke() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (membershipId: number) =>
      apiFetch(`/api/v1/admin/memberships/${membershipId}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: queryKeys.adminUsers }),
  })
}
