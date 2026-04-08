// Browser Web Speech API wrapper for the AI tutor's voice. Picked instead
// of a server-side TTS proxy because it has no quota, no API key, and no
// billing requirement — important for an open-ended demo. The trade-off is
// that voice quality depends on the OS/browser; Mac Chrome (Samantha) and
// modern Edge sound natural, Linux defaults are rougher.
//
// We expose a tiny imperative API:
//   - speak(text): cancels any current utterance, picks a good English
//     voice if one is available, and starts speaking. Returns a Promise
//     that resolves when the utterance ends.
//   - stop(): cancels whatever is currently playing.
//   - isSupported(): feature-detect; the conversation page falls back to a
//     text-only experience if speech synthesis is unavailable.

let cachedVoice: SpeechSynthesisVoice | null = null

function pickVoice(): SpeechSynthesisVoice | null {
  if (cachedVoice) return cachedVoice
  if (typeof window === 'undefined' || !('speechSynthesis' in window)) return null
  const voices = window.speechSynthesis.getVoices()
  if (voices.length === 0) return null

  // Prefer high-quality natural English voices in this rough order.
  const preferred = [
    'Samantha',          // macOS
    'Google US English', // Chrome
    'Microsoft Aria Online (Natural) - English (United States)',
    'Microsoft Jenny Online (Natural) - English (United States)',
  ]
  for (const name of preferred) {
    const v = voices.find((vv) => vv.name === name)
    if (v) return (cachedVoice = v)
  }
  // Fall back to any en-US voice, then any English voice, then anything.
  const enUs = voices.find((v) => v.lang === 'en-US')
  if (enUs) return (cachedVoice = enUs)
  const en = voices.find((v) => v.lang.startsWith('en'))
  if (en) return (cachedVoice = en)
  return (cachedVoice = voices[0] ?? null)
}

export function isSupported(): boolean {
  return typeof window !== 'undefined' && 'speechSynthesis' in window
}

export function stop(): void {
  if (!isSupported()) return
  window.speechSynthesis.cancel()
}

export function speak(text: string): Promise<void> {
  if (!isSupported() || !text.trim()) return Promise.resolve()
  stop()

  return new Promise((resolve) => {
    const utter = new SpeechSynthesisUtterance(text)
    const voice = pickVoice()
    if (voice) {
      utter.voice = voice
      utter.lang = voice.lang
    } else {
      utter.lang = 'en-US'
    }
    utter.rate = 1.0
    utter.pitch = 1.0
    utter.onend = () => resolve()
    utter.onerror = () => resolve() // never reject — playback failures
                                    // shouldn't break the conversation flow
    window.speechSynthesis.speak(utter)
  })
}

// Some browsers populate the voice list asynchronously after page load;
// call this once at startup to warm the cache.
export function warmVoices(): void {
  if (!isSupported()) return
  // Trigger an initial fetch
  window.speechSynthesis.getVoices()
  window.speechSynthesis.onvoiceschanged = () => {
    cachedVoice = null
    pickVoice()
  }
}
