// Wire types matching the Rails API responses. Kept hand-written instead of
// codegen because the surface is small and it's clearer for reviewers.

export type Feature = 'study' | 'talk' | 'analysis'

export type MembershipPlan = {
  id: number
  name: string
  price_cents: number
  duration_days: number
  features: Feature[]
}

export type MembershipState = 'active' | 'expired' | 'revoked'

export type Membership = {
  id: number
  plan: { id: number; name: string; features: Feature[] }
  state: MembershipState
  source: 'purchase' | 'admin_grant'
  started_at: string
  expires_at: string
}

export type User = {
  id: number
  email: string
  name: string
  role: 'user' | 'admin'
}

export type MeResponse = {
  user: User
  memberships: Membership[]
  features: Feature[]
}

export type AdminUser = User & { memberships: Membership[] }
