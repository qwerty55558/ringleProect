// Thin wrapper around fetch that:
//   - prefixes the base URL from VITE_API_BASE_URL
//   - injects the X-User-Id header (we have no real auth per the spec)
//   - decodes JSON / surfaces a typed ApiError so callers can branch on .status
//
// We deliberately keep this small — components/hooks layer their own retry
// and abort logic on top via react-query and AbortController.

import { useUserStore } from './userStore'

const BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '')

export class ApiError extends Error {
  status: number
  body: unknown
  constructor(status: number, body: unknown, message: string) {
    super(message)
    this.status = status
    this.body = body
  }
}

type RequestOptions = Omit<RequestInit, 'body'> & {
  body?: unknown
  query?: Record<string, string | number | undefined>
  formData?: FormData
}

function authHeaders(): Record<string, string> {
  const id = useUserStore.getState().currentUserId
  return id ? { 'X-User-Id': String(id) } : {}
}

function buildUrl(path: string, query?: RequestOptions['query']): string {
  const url = new URL(path.startsWith('/') ? path : `/${path}`, BASE_URL)
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined) url.searchParams.set(k, String(v))
    }
  }
  return url.toString()
}

export async function apiFetch<T = unknown>(path: string, opts: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json', ...authHeaders() }
  let body: BodyInit | undefined

  if (opts.formData) {
    body = opts.formData
  } else if (opts.body !== undefined) {
    headers['Content-Type'] = 'application/json'
    body = JSON.stringify(opts.body)
  }

  const res = await fetch(buildUrl(path, opts.query), {
    method: opts.method ?? 'GET',
    headers: { ...headers, ...(opts.headers as Record<string, string> | undefined) },
    body,
    signal: opts.signal,
  })

  if (!res.ok) {
    let parsed: unknown = null
    try {
      parsed = await res.json()
    } catch {
      /* ignore */
    }
    throw new ApiError(res.status, parsed, `Request failed: ${res.status}`)
  }

  if (res.status === 204) return undefined as T
  const ct = res.headers.get('content-type') ?? ''
  if (ct.includes('application/json')) return (await res.json()) as T
  return (await res.blob()) as unknown as T
}

export async function translateText(text: string): Promise<string> {
  const res = await apiFetch<{ translation: string; cache: string }>('/api/v1/ai/translations', {
    method: 'POST',
    body: { text },
  })
  return res.translation
}

// Streams a Server-Sent Events response from POST /api/v1/ai/messages,
// yielding text deltas one chunk at a time. Resolves when the server
// emits the `done` event or the response stream closes. Accepts an
// optional `studyMaterialId` so a /study?study=:id session can prime
// the assistant's system prompt with the chosen curriculum.
export async function streamAiMessages(
  messages: Array<{ role: 'user' | 'assistant'; text: string }>,
  onDelta: (chunk: string) => void,
  opts: { signal?: AbortSignal; studyMaterialId?: number; conversationId?: number } = {},
): Promise<void> {
  const body: Record<string, unknown> = { messages }
  if (opts.studyMaterialId !== undefined) body.study_material_id = opts.studyMaterialId
  if (opts.conversationId !== undefined) body.conversation_id = opts.conversationId

  const res = await fetch(buildUrl('/api/v1/ai/messages'), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
      ...authHeaders(),
    },
    body: JSON.stringify(body),
    signal: opts.signal,
  })
  if (!res.ok || !res.body) {
    throw new ApiError(res.status, null, `AI stream failed: ${res.status}`)
  }

  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  let currentEvent = 'message'

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })

    let idx
    while ((idx = buffer.indexOf('\n')) !== -1) {
      const line = buffer.slice(0, idx).trim()
      buffer = buffer.slice(idx + 1)
      if (line === '') {
        currentEvent = 'message'
        continue
      }
      if (line.startsWith('event:')) {
        currentEvent = line.slice(6).trim()
        continue
      }
      if (line.startsWith('data:')) {
        const payload = line.slice(5).trim()
        if (!payload) continue
        if (currentEvent === 'done') return
        if (currentEvent === 'error') {
          throw new ApiError(502, payload, 'AI stream error')
        }
        try {
          const obj = JSON.parse(payload) as { delta?: string }
          if (obj.delta) onDelta(obj.delta)
        } catch {
          /* ignore malformed frame */
        }
      }
    }
  }
}
