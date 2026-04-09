import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { StudyPage } from './StudyPage'
import { useUserStore } from '../lib/userStore'

const SAMPLE = {
  seeded: [
    {
      id: 1,
      slug: 'introduce-yourself',
      title: 'Introducing Yourself at Work',
      level: 'beginner',
      category: 'business',
      description: '동료에게 본인을 소개해보세요.',
      scenario_prompt: 'You are Ringle...',
      key_expressions: ["Hi, I'm ___ ."],
      example_dialogue: [{ role: 'assistant', text: 'Hi! What do you do?' }],
      ai_generated: false,
    },
    {
      id: 2,
      slug: 'ordering-coffee',
      title: 'Ordering Coffee on the Go',
      level: 'novice',
      category: 'daily',
      description: '카페에서 음료를 주문해보세요.',
      scenario_prompt: 'You are a barista...',
      key_expressions: ['Can I get a ___ ?'],
      example_dialogue: [{ role: 'assistant', text: 'Hi there!' }],
      ai_generated: false,
    },
  ],
  ai_generated: [],
}

function renderStudy(qc: QueryClient) {
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <StudyPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function meFixture(features: Array<'study' | 'talk' | 'analysis'>) {
  return {
    user: { id: 1, name: 'Danny', email: 'd@x', role: 'user' },
    memberships: [],
    features,
    study_generations: { used: 0, limit: 3, remaining: 3 },
  }
}

function mockApi(meFeatures: Array<'study' | 'talk' | 'analysis'>) {
  return vi.spyOn(globalThis, 'fetch').mockImplementation((input) => {
    const url = String((input as Request).url ?? input)
    if (url.endsWith('/api/v1/study_materials')) {
      return Promise.resolve(
        new Response(JSON.stringify(SAMPLE), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
      )
    }
    if (url.endsWith('/api/v1/me')) {
      return Promise.resolve(
        new Response(JSON.stringify(meFixture(meFeatures)), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
      )
    }
    return Promise.reject(new Error(`unexpected url ${url}`))
  })
}

describe('StudyPage', () => {
  beforeEach(() => {
    useUserStore.setState({ currentUserId: 1 })
  })
  afterEach(() => vi.restoreAllMocks())

  it('shows the conversation CTA only for users with the talk feature', async () => {
    mockApi(['study', 'talk'])
    renderStudy(new QueryClient({ defaultOptions: { queries: { retry: false } } }))

    await waitFor(() =>
      expect(screen.getAllByText('Introducing Yourself at Work').length).toBeGreaterThan(0),
    )
    expect(screen.getByText('Ordering Coffee on the Go')).toBeInTheDocument()
    expect(screen.getByText(/동료에게 본인을 소개/)).toBeInTheDocument()

    // Talk-tier user sees the conversation CTA + the new TTS button
    expect(screen.getByRole('button', { name: /핵심 표현 듣기/ })).toBeInTheDocument()
    const cta = screen.getByRole('link', { name: /AI 와 대화로 학습 시작/ })
    expect(cta).toHaveAttribute('href', '/conversation?study=1')
  })

  it('hides the conversation CTA for study-only users and only shows the TTS button', async () => {
    mockApi(['study'])
    renderStudy(new QueryClient({ defaultOptions: { queries: { retry: false } } }))

    await waitFor(() =>
      expect(screen.getAllByText('Introducing Yourself at Work').length).toBeGreaterThan(0),
    )

    expect(screen.getByRole('button', { name: /핵심 표현 듣기/ })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /AI 와 대화로 학습 시작/ })).toBeNull()
  })
})
