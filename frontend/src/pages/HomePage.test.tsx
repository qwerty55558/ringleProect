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
    useUserStore.setState({ currentUserId: 1 })
  })
  afterEach(() => vi.restoreAllMocks())

  it('renders memberships and plans, and triggers a purchase', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation((input) => {
      const url = String((input as Request).url ?? input)
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
          new Response(JSON.stringify({ payment: { id: 99 }, membership: { id: 33 } }), {
            status: 201,
            headers: { 'content-type': 'application/json' },
          }),
        )
      }
      return Promise.reject(new Error(`unexpected url ${url}`))
    })

    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    renderWith(qc)

    await waitFor(() => expect(screen.getByText(/Danny/)).toBeInTheDocument())
    expect(screen.getByText('Premium Plus')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: /구매하기/ }))

    await waitFor(() => {
      const calls = fetchSpy.mock.calls.map((c) => String((c[0] as Request).url ?? c[0]))
      expect(calls.some((u) => u.endsWith('/api/v1/payments'))).toBe(true)
    })
  })
})
