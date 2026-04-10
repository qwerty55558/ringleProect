// Per-turn audio cache + TTS fetch helper.
//
// Two responsibilities:
//   1. fetchTtsBlob — fire a TTS request the moment a sentence is ready,
//      so AudioQueue can start playing as soon as the network round-trip
//      completes.
//   2. rememberAudio / getCachedAudio — keep one Blob per turn id (any
//      kind: ElevenLabs MP3 for the assistant, raw WAV from the user mic)
//      so the per-bubble replay button can re-play it without re-hitting
//      the network or re-recording.

import { apiFetch } from './api'
import { speak } from './speech'

export function fetchTtsBlob(text: string, signal?: AbortSignal): Promise<Blob> {
  return apiFetch<Blob>('/api/v1/ai/speech', {
    method: 'POST',
    body: { text },
    signal,
  })
}

// ElevenLabs → blob. On failure → browser SpeechSynthesis fallback.
// Returns Blob when ElevenLabs succeeds (cacheable), null when fallback
// played (audio went through speakers but no blob to cache).
export async function fetchTtsWithFallback(text: string, signal?: AbortSignal): Promise<Blob | null> {
  try {
    return await fetchTtsBlob(text, signal)
  } catch {
    await speak(text)
    return null
  }
}

const cache = new Map<string, Blob>()

export function rememberAudio(id: string, blob: Blob): void {
  cache.set(id, blob)
}

export function getCachedAudio(id: string): Blob | undefined {
  return cache.get(id)
}

export function clearAudioCache(): void {
  cache.clear()
}
