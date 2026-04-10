// Wire types matching the Rails API responses. Kept hand-written instead of
// codegen because the surface is small and it's clearer for reviewers.

export type Feature = 'study' | 'talk' | 'analysis'

export type MembershipPlan = {
  id: number
  name: string
  price_cents: number
  duration_days: number
  // Sub-day plans (e.g. "Test 30s Expiry") populate this; ordinary day-
  // based plans leave it null. The UI prefers `duration_label` for
  // display when present.
  duration_seconds: number | null
  duration_label?: string
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
  // Per-user lifetime cap on AI study topic generation. Surfaced here
  // so the StudyPage can render "남은 횟수: N/3" without an extra fetch.
  study_generations: {
    used: number
    limit: number
    remaining: number
  }
}

export type AdminUser = User & { memberships: Membership[] }

// ─── Conversation persistence ─────────────────────────────────────────
// Mirrors the Rails Conversation / Message rows. `audio_url` is a path
// (not a fully-qualified URL) into our own /messages/:id/audio endpoint —
// we deliberately don't use Active Storage's public URLs so the API can
// enforce per-user ownership on every byte we serve.
export type ConversationMessage = {
  id: number
  role: 'user' | 'assistant'
  text: string
  position: number
  created_at: string
  audio_url: string | null
}

export type Conversation = {
  id: number
  title: string | null
  created_at: string
  messages?: ConversationMessage[]
}

// ─── Payments ─────────────────────────────────────────────────────────
// Each entry maps 1:1 onto PaymentGateway::TEST_CARDS in Rails.
// Shape returned by POST /api/v1/payments on success — drives the
// success step in the checkout modal.
export type PurchaseResponse = {
  payment: {
    id: number
    amount_cents: number
    status: string
    pg_transaction_id: string
    card_brand: string
  }
  membership: {
    id: number
    plan_id: number
    started_at: string
    expires_at: string
    state: MembershipState
  }
}

export type TestCard = {
  token: string
  label: string
  outcome: 'success' | 'declined' | 'processing'
  // Mock checkout fixtures: the modal renders these as if the user had
  // typed them in. They are dummy values — the real PG handshake is still
  // token-based on the backend.
  brand: string
  number: string
  expiry: string
  cvc: string
  holder: string
}

// ─── STT demo fixtures ───────────────────────────────────────────────
// Pre-seeded "as if I spoke into the mic" examples. The audio is a
// deterministic synthesised WAV (so the SHA256 lines up with the cache
// table) and the text is whatever the cache resolves it to. The
// frontend uses these to demo the conversation flow without having to
// expose a microphone in the office.
export type SttFixture = {
  slug: string
  label: string
  text: string
  mime_type: string
  byte_size: number
  audio_url: string
}

// ─── Study curriculum ────────────────────────────────────────────────
// Cached study material rows. The Generate service in Rails calls Gemini
// once per topic and caches the result, so the front-end always reads
// from the same shape regardless of whether the row was hand-seeded or
// AI-generated.
export type StudyDialogueLine = { role: 'user' | 'assistant'; text: string }

export type StudyLevel = 'novice' | 'beginner' | 'intermediate' | 'advanced'
export type StudyCategory = 'daily' | 'business' | 'travel' | 'hobby' | 'academic' | 'conversation'

export type StudyMaterial = {
  id: number
  slug: string
  title: string
  level: StudyLevel
  category: StudyCategory
  description: string
  scenario_prompt: string
  key_expressions: string[]
  example_dialogue: StudyDialogueLine[]
  ai_generated: boolean
}

// New shape for /api/v1/study_materials — split into seeded vs
// AI-generated buckets so the StudyPage can render them as distinct
// sections instead of a flat list.
export type StudyMaterialsResponse = {
  seeded: StudyMaterial[]
  ai_generated: StudyMaterial[]
}
