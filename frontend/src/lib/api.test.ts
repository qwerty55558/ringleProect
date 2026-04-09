import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError, apiFetch, streamAiMessages } from './api'
import { useUserStore } from './userStore'

describe('apiFetch', () => {
  beforeEach(() => {
    useUserStore.setState({ currentUserId: 42 })
  })
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('sends X-User-Id and JSON body, parses JSON response', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    )

    const out = await apiFetch<{ ok: boolean }>('/api/v1/payments', {
      method: 'POST',
      body: { membership_plan_id: 1 },
    })

    expect(out).toEqual({ ok: true })
    const call = fetchSpy.mock.calls[0]
    const headers = (call[1] as RequestInit).headers as Record<string, string>
    expect(headers['X-User-Id']).toBe('42')
    expect(headers['Content-Type']).toBe('application/json')
    expect((call[1] as RequestInit).body).toBe('{"membership_plan_id":1}')
  })

  it('throws ApiError with the parsed body on non-2xx', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ error: 'forbidden' }), {
        status: 403,
        headers: { 'content-type': 'application/json' },
      }),
    )

    await expect(apiFetch('/api/v1/me')).rejects.toMatchObject({
      status: 403,
      body: { error: 'forbidden' },
    })
  })

  it('returns a Blob for non-JSON responses (TTS)', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(new Uint8Array([1, 2, 3]), {
        status: 200,
        headers: { 'content-type': 'audio/wav' },
      }),
    )

    const blob = await apiFetch<Blob>('/api/v1/ai/speech', { method: 'POST', body: { text: 'hi' } })
    expect(blob).toHaveProperty('size')
    expect(blob).toHaveProperty('type')
  })
})

describe('streamAiMessages', () => {
  it('parses SSE deltas and stops on the done event', async () => {
    const sse =
      'event: message\ndata: {"delta":"Hello "}\n\n' +
      'event: message\ndata: {"delta":"world"}\n\n' +
      'event: done\ndata: {}\n\n'
    const encoder = new TextEncoder()
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode(sse))
        controller.close()
      },
    })
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(stream, { status: 200, headers: { 'content-type': 'text/event-stream' } }),
    )

    const collected: string[] = []
    await streamAiMessages([{ role: 'user', text: 'hi' }], (d) => collected.push(d))
    expect(collected).toEqual(['Hello ', 'world'])
  })

  it('throws ApiError on a non-2xx response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('forbidden', { status: 403 }))
    await expect(streamAiMessages([], () => undefined)).rejects.toBeInstanceOf(ApiError)
  })
})
