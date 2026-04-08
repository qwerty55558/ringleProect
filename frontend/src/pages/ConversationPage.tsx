// Conversation page — the central UX of the assignment.
//
// Per turn:
//   1. user presses Mic → useVoiceRecorder starts MicVAD + waveform
//   2. user speaks; vad-web keeps only the voiced segments
//   3. user presses 답변완료 → finalize() returns a 16kHz WAV
//   4. POST /api/v1/ai/transcriptions → STT text (shown immediately)
//   5. POST /api/v1/ai/messages (SSE) → stream the assistant reply
//      AS each sentence completes during the stream, fire a TTS request
//      in parallel and push it onto an in-order playback queue, so the
//      first audio reaches the user within ~1s of the LLM's first token.
//   6. Per-message replay button reuses the cached MP3 blob (no extra
//      ElevenLabs hit).

import { useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { ApiError, apiFetch, streamAiMessages } from '../lib/api'
import { useMe } from '../lib/queries'
import { useVoiceRecorder } from '../lib/useVoiceRecorder'
import { AudioQueue } from '../lib/audioQueue'
import { SentenceSplitter } from '../lib/sentences'
import { fetchTtsBlob, getCachedTts, rememberTts } from '../lib/ttsCache'

const GREETING = "Hi! I'm Ringle, your English speaking partner. What's your name and what do you do?"

type Turn = {
  id: string
  role: 'user' | 'assistant'
  text: string
  pending?: boolean
}

export function ConversationPage() {
  const me = useMe()
  const recorder = useVoiceRecorder()
  const [turns, setTurns] = useState<Turn[]>([])
  const [status, setStatus] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const greetingPlayed = useRef(false)
  const threadRef = useRef<HTMLDivElement>(null)
  const queue = useMemo(() => new AudioQueue(), [])

  useEffect(() => {
    return () => queue.stop()
  }, [queue])

  useEffect(() => {
    threadRef.current?.scrollTo({ top: threadRef.current.scrollHeight, behavior: 'smooth' })
  }, [turns])

  if (me.isLoading) {
    return (
      <div className="empty-state">
        <div className="spinner" /> Checking membership…
      </div>
    )
  }
  if (!me.data) return <p className="muted">Pick an account from the top bar to continue.</p>
  if (!me.data.features.includes('talk')) return <NoMembership />

  // Speak the canned opener exactly once on first render.
  if (!greetingPlayed.current && turns.length === 0) {
    greetingPlayed.current = true
    const id = 'greeting'
    setTurns([{ id, role: 'assistant', text: GREETING }])
    queue.reset()
    queue.enqueue(
      fetchTtsBlob(GREETING).then((blob) => {
        rememberTts(id, blob)
        return blob
      }),
    )
  }

  const handleStart = async () => {
    setError(null)
    queue.stop()
    queue.reset()
    await recorder.start()
  }

  const handleSubmit = async () => {
    if (busy) return
    setBusy(true)
    setStatus('Transcribing…')

    try {
      const wav = await recorder.finalize()
      if (!wav) {
        setStatus('')
        setError('음성을 감지하지 못했어요. 마이크에 가깝게, 조금 더 길게 말해보세요.')
        setBusy(false)
        return
      }

      const fd = new FormData()
      fd.append('audio', wav, 'speech.wav')
      const stt = await apiFetch<{ text: string }>('/api/v1/ai/transcriptions', {
        method: 'POST',
        formData: fd,
      })

      const userTurn: Turn = { id: crypto.randomUUID(), role: 'user', text: stt.text }
      const assistantId = crypto.randomUUID()
      setTurns((prev) => [
        ...prev,
        userTurn,
        { id: assistantId, role: 'assistant', text: '', pending: true },
      ])

      setStatus('Thinking…')
      const history = [...turns, userTurn].map((t) => ({ role: t.role, text: t.text }))

      // Stream LLM tokens; whenever a sentence completes we kick off TTS
      // for it in parallel and let AudioQueue play them back in order.
      queue.reset()
      const splitter = new SentenceSplitter()
      const sentenceBlobs: Promise<Blob>[] = []
      let acc = ''

      await streamAiMessages(history, (delta) => {
        acc += delta
        setTurns((prev) =>
          prev.map((t) => (t.id === assistantId ? { ...t, text: acc } : t)),
        )
        for (const sentence of splitter.feed(delta)) {
          const p = fetchTtsBlob(sentence)
          sentenceBlobs.push(p)
          queue.enqueue(p)
        }
      })

      const tail = splitter.flush()
      if (tail) {
        const p = fetchTtsBlob(tail)
        sentenceBlobs.push(p)
        queue.enqueue(p)
      }

      setTurns((prev) =>
        prev.map((t) => (t.id === assistantId ? { ...t, pending: false } : t)),
      )
      setStatus('')

      // Stitch all the per-sentence blobs into one cached blob for replay.
      void Promise.all(sentenceBlobs).then((blobs) => {
        if (blobs.length === 0) return
        rememberTts(assistantId, new Blob(blobs, { type: 'audio/mpeg' }))
      })
    } catch (e: unknown) {
      setError(formatError(e))
      setStatus('')
    } finally {
      setBusy(false)
    }
  }

  const handleReplay = (id: string, text: string) => {
    queue.stop()
    queue.reset()
    const cached = getCachedTts(id)
    if (cached) {
      queue.enqueue(Promise.resolve(cached))
    } else {
      queue.enqueue(
        fetchTtsBlob(text).then((blob) => {
          rememberTts(id, blob)
          return blob
        }),
      )
    }
  }

  const recording = recorder.state === 'recording' || recorder.state === 'starting'

  return (
    <div className="conv">
      <div className="conv-thread" ref={threadRef}>
        {turns.length === 0 && <div className="empty-state">Loading conversation…</div>}
        {turns.map((t) => (
          <div key={t.id} className={`bubble ${t.role}`}>
            <div className="text">
              {t.text}
              {t.pending && <span className="dot-pulse" aria-hidden />}
            </div>
            {t.role === 'assistant' && t.text && !t.pending && (
              <button
                className="replay"
                aria-label="Replay"
                onClick={() => handleReplay(t.id, t.text)}
              >
                ▶
              </button>
            )}
          </div>
        ))}
      </div>

      <div className="conv-controls">
        {error && <div className="error-banner">{error}</div>}
        {status && (
          <div className="status-pill">
            <div className="spinner" /> {status}
          </div>
        )}

        {recording ? (
          <>
            <Waveform values={recorder.amplitudes} />
            <div className="mic-row">
              <button className="btn ghost" onClick={recorder.cancel}>
                취소
              </button>
              <button className="btn primary big" onClick={handleSubmit} disabled={busy}>
                답변 완료
              </button>
            </div>
          </>
        ) : (
          <>
            <p className="muted">마이크를 눌러 영어로 말해보세요.</p>
            <button
              className="mic-btn"
              onClick={handleStart}
              aria-label="Start recording"
              disabled={busy}
            >
              <MicIcon />
            </button>
          </>
        )}
      </div>
    </div>
  )
}

function Waveform({ values }: { values: number[] }) {
  // Mirror the values around the center to give a symmetric, fuller look
  return (
    <div className="waveform" role="img" aria-label="Live audio waveform">
      {values.map((v, i) => (
        <div key={i} className="bar" style={{ height: `${v}px` }} />
      ))}
    </div>
  )
}

function MicIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" />
      <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
      <line x1="12" y1="19" x2="12" y2="23" />
      <line x1="8" y1="23" x2="16" y2="23" />
    </svg>
  )
}

function NoMembership() {
  return (
    <div className="card">
      <h2>Talk 멤버십이 필요해요</h2>
      <p className="muted">
        대화 기능은 <code>talk</code> 권한이 포함된 활성 멤버십이 있어야 사용할 수 있어요.
      </p>
      <Link to="/" className="btn primary">
        플랜 보러가기
      </Link>
    </div>
  )
}

function formatError(e: unknown): string {
  if (e instanceof ApiError) {
    if (e.status === 429) return '요청이 너무 빨라요. 잠시 후 다시 시도해주세요.'
    if (e.status === 403) return 'Talk 멤버십이 없어요.'
    if (e.status === 502) return 'AI 서비스가 일시적으로 응답하지 않습니다.'
    return `요청 실패 (${e.status}).`
  }
  if (e instanceof Error) return e.message
  return '문제가 발생했어요.'
}
