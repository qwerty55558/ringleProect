// Conversation persistence client.
//
// Wraps the Rails Conversation/Message endpoints behind a small typed
// surface. Used by ConversationPage to:
//   - hydrate prior turns on mount (replays survive a reload)
//   - persist each new turn (user mic upload + assistant TTS blob)
//   - explicitly delete the whole thread when the user resets
//
// The audio path returned in `audio_url` is relative to the API base URL
// (e.g. "/api/v1/conversations/12/messages/45/audio") — call
// `audioBlobUrl()` to turn it into something a <audio> element can play.

import { apiFetch } from './api'
import type { Conversation, ConversationMessage } from './types'

const API_BASE = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '')

export function createConversation(title?: string): Promise<Conversation> {
  return apiFetch<Conversation>('/api/v1/conversations', {
    method: 'POST',
    body: title ? { title } : {},
  })
}

export function getConversation(id: number): Promise<Conversation> {
  return apiFetch<Conversation>(`/api/v1/conversations/${id}`)
}

export function deleteConversation(id: number): Promise<void> {
  return apiFetch<void>(`/api/v1/conversations/${id}`, { method: 'DELETE' })
}

// Persist a turn. The Rails endpoint accepts multipart so a single call
// stores text + audio + role + position together; on success it returns
// the canonical Message row (with the server-assigned id we'll use as
// the local turn id).
export async function appendMessage(args: {
  conversationId: number
  role: 'user' | 'assistant'
  text: string
  audio?: Blob
  audioFilename?: string
}): Promise<ConversationMessage> {
  const fd = new FormData()
  fd.append('role', args.role)
  fd.append('text', args.text)
  if (args.audio) {
    fd.append('audio', args.audio, args.audioFilename ?? `${args.role}.bin`)
  }
  return apiFetch<ConversationMessage>(
    `/api/v1/conversations/${args.conversationId}/messages`,
    { method: 'POST', formData: fd },
  )
}

// Fetches the cached audio blob for a persisted message via our own
// authenticated endpoint. Throws ApiError if the blob is gone (e.g. the
// conversation was deleted on another tab).
export async function fetchMessageAudio(audioPath: string): Promise<Blob> {
  return apiFetch<Blob>(audioPath)
}

// Convenience: turn the relative audio_url into something an <audio>
// element can play. We don't use this in the current code (we always
// fetch the blob through apiFetch so the X-User-Id header is attached),
// but it's exposed for places where the URL is enough.
export function audioBlobUrl(audioPath: string): string {
  return `${API_BASE}${audioPath}`
}
