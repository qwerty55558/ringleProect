import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { TopBar } from './TopBar'
import { useUserStore } from '../lib/userStore'
import type { Feature } from '../lib/types'

function renderTopBar(qc: QueryClient) {
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <TopBar />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function stubMe(features: Feature[], role: 'user' | 'admin' = 'user') {
  vi.spyOn(globalThis, 'fetch').mockImplementation((input) => {
    const url = String((input as Request).url ?? input)
    if (url.endsWith('/api/v1/me')) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            user: { id: 1, name: 'Danny', email: 'd@x', role },
            memberships: [],
            features,
          }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        ),
      )
    }
    if (url.endsWith('/api/v1/admin/users')) {
      return Promise.resolve(
        new Response(JSON.stringify([]), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
      )
    }
    return Promise.reject(new Error(`unexpected url ${url}`))
  })
}

describe('TopBar dynamic feature tabs', () => {
  beforeEach(() => {
    useUserStore.setState({ currentUserId: 1 })
  })
  afterEach(() => vi.restoreAllMocks())

  it('renders only the home tab for a user with no features', async () => {
    stubMe([])
    renderTopBar(new QueryClient({ defaultOptions: { queries: { retry: false } } }))
    await waitFor(() => expect(screen.getByText('홈')).toBeInTheDocument())
    expect(screen.queryByText('학습')).not.toBeInTheDocument()
    expect(screen.queryByText('대화')).not.toBeInTheDocument()
    expect(screen.queryByText('분석')).not.toBeInTheDocument()
    expect(screen.queryByText('관리자')).not.toBeInTheDocument()
  })

  it('renders study + talk tabs for a learner with study and talk features', async () => {
    stubMe(['study', 'talk'])
    renderTopBar(new QueryClient({ defaultOptions: { queries: { retry: false } } }))
    await waitFor(() => expect(screen.getByText('학습')).toBeInTheDocument())
    expect(screen.getByText('대화')).toBeInTheDocument()
    expect(screen.queryByText('분석')).not.toBeInTheDocument()
    expect(screen.queryByText('관리자')).not.toBeInTheDocument()
  })

  it('renders the analysis tab when the analysis feature is granted', async () => {
    stubMe(['study', 'talk', 'analysis'])
    renderTopBar(new QueryClient({ defaultOptions: { queries: { retry: false } } }))
    await waitFor(() => expect(screen.getByText('분석')).toBeInTheDocument())
  })

  it('renders the admin tab only for admin role', async () => {
    stubMe(['study', 'talk'], 'admin')
    renderTopBar(new QueryClient({ defaultOptions: { queries: { retry: false } } }))
    await waitFor(() => expect(screen.getByText('관리자')).toBeInTheDocument())
  })
})
