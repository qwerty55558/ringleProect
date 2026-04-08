// Centralized react-query hooks. Keeping query keys in one place avoids
// stale-cache surprises and makes invalidations cheap to reason about.

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from './api'
import { useUserStore } from './userStore'
import type { AdminUser, MeResponse, MembershipPlan } from './types'

export const queryKeys = {
  me: (id: number | null) => ['me', id] as const,
  plans: ['membershipPlans'] as const,
  adminUsers: ['admin', 'users'] as const,
}

export function useMe() {
  const userId = useUserStore((s) => s.currentUserId)
  return useQuery({
    queryKey: queryKeys.me(userId),
    queryFn: () => apiFetch<MeResponse>('/api/v1/me'),
    enabled: userId !== null,
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
    mutationFn: (planId: number) =>
      apiFetch('/api/v1/payments', { method: 'POST', body: { membership_plan_id: planId } }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.me(userId) })
      qc.invalidateQueries({ queryKey: queryKeys.adminUsers })
    },
  })
}

export function useAdminGrant() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (vars: { userId: number; planId: number; durationDays?: number }) =>
      apiFetch('/api/v1/admin/memberships', {
        method: 'POST',
        body: {
          user_id: vars.userId,
          membership_plan_id: vars.planId,
          duration_days: vars.durationDays,
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
