// In-flight TTS request manager.
//
// Two responsibilities:
//   1. Fire a TTS request as a Promise<Blob> the moment a sentence is ready,
//      so the audio queue can start playing as soon as the network round-trip
//      completes.
//   2. Cache the resolved blobs by message id so the user can hit the
//      replay button without paying for another ElevenLabs request.

import { apiFetch } from './api'

export function fetchTtsBlob(text: string, signal?: AbortSignal): Promise<Blob> {
  return apiFetch<Blob>('/api/v1/ai/speech', {
    method: 'POST',
    body: { text },
    signal,
  })
}

// Per-message TTS cache. We keep one Blob per assistant turn id; calling
// `replay` reuses it instead of hitting the network again.
const cache = new Map<string, Blob>()

export function rememberTts(id: string, blob: Blob): void {
  cache.set(id, blob)
}

export function getCachedTts(id: string): Blob | undefined {
  return cache.get(id)
}

export function clearTtsCache(): void {
  cache.clear()
}
