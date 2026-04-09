import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { HomePage } from './HomePage'
import { useUserStore } from '../lib/userStore'

function renderWith(qc: QueryClient) {
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <HomePage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('HomePage', () => {
  beforeEach(() => {
    useUserStore.setState({ currentUserId: 1, selectedCardToken: 'tok_visa' })
  })
  afterEach(() => vi.restoreAllMocks())

  it('renders memberships and plans, and triggers a purchase with the chosen test card', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation((input) => {
      const url = String((input as Request).url ?? input)
      if (url.endsWith('/api/v1/payments/test_cards')) {
        return Promise.resolve(
          new Response(
            JSON.stringify([
              {
                token: 'tok_visa',
                label: '정상 카드 (Visa)',
                outcome: 'success',
                brand: 'Visa',
                number: '4242 4242 4242 4242',
                expiry: '12/29',
                cvc: '123',
                holder: 'RINGLE DEMO',
              },
            ]),
            { status: 200, headers: { 'content-type': 'application/json' } },
          ),
        )
      }
      if (url.endsWith('/api/v1/me')) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              user: { id: 1, name: 'Danny', email: 'd@x', role: 'user' },
              memberships: [],
              features: [],
            }),
            { status: 200, headers: { 'content-type': 'application/json' } },
          ),
        )
      }
      if (url.endsWith('/api/v1/membership_plans')) {
        return Promise.resolve(
          new Response(
            JSON.stringify([
              { id: 7, name: 'Premium Plus', price_cents: 1_000, duration_days: 60, features: ['study', 'talk'] },
            ]),
            { status: 200, headers: { 'content-type': 'application/json' } },
          ),
        )
      }
      if (url.endsWith('/api/v1/payments')) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              payment: {
                id: 99,
                amount_cents: 1_000,
                status: 'succeeded',
                pg_transaction_id: 'mock_pg_abc123',
                card_brand: 'Visa',
              },
              membership: {
                id: 33,
                plan_id: 7,
                started_at: '2026-04-09T00:00:00Z',
                expires_at: '2026-06-08T00:00:00Z',
                state: 'active',
              },
            }),
            { status: 201, headers: { 'content-type': 'application/json' } },
          ),
        )
      }
      return Promise.reject(new Error(`unexpected url ${url}`))
    })

    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    renderWith(qc)

    await waitFor(() => expect(screen.getByText(/Danny/)).toBeInTheDocument())
    expect(screen.getByText('Premium Plus')).toBeInTheDocument()

    // Step 1: open the checkout modal from the plan card.
    await userEvent.click(screen.getByRole('button', { name: /구매하기/ }))
    // Step 2: confirm inside the modal — the modal pre-fills the card
    // fields, the user just hits the confirm CTA.
    await waitFor(() => expect(screen.getByRole('dialog')).toBeInTheDocument())
    await userEvent.click(screen.getByRole('button', { name: /확인하고 결제/ }))

    // Step 3: modal flips to the receipt step on success — verify the
    // headline and the transaction id are rendered before we move on.
    await waitFor(() => expect(screen.getByText('결제가 완료되었어요')).toBeInTheDocument())
    expect(screen.getByText('mock_pg_abc123')).toBeInTheDocument()

    await waitFor(() => {
      const calls = fetchSpy.mock.calls.map((c) => String((c[0] as Request).url ?? c[0]))
      expect(calls.some((u) => u.endsWith('/api/v1/payments'))).toBe(true)
    })

    // The purchase request should have included the chosen card_token in
    // payment_method, not a bare membership_plan_id.
    const purchaseCall = fetchSpy.mock.calls.find((c) =>
      String((c[0] as Request).url ?? c[0]).endsWith('/api/v1/payments'),
    )!
    const init = purchaseCall[1] as RequestInit
    const body = JSON.parse(String(init.body))
    expect(body.payment_method.card_token).toBe('tok_visa')
  })
})
