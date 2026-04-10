// Conversation page — the central UX of the assignment.
//
// Per turn:
//   1. user presses Mic → useVoiceRecorder starts MicVAD + waveform
//      (or picks a "예문" fixture, which plays a pre-recorded WAV
//       through Web Audio so the same waveform UI animates and the
//       same downstream pipeline runs)
//   2. user speaks; vad-web keeps only the voiced segments
//   3. user presses 답변완료 → finalize() returns a 16kHz WAV
//      (fixture path skips this — playback ends auto-finalises)
//   4. POST /api/v1/ai/transcriptions → STT text. Backend hits the
//      Stt::Transcribe cache so identical bytes (every fixture, every
//      replay) return X-Stt-Cache: hit without billing Gemini.
//   5. POST /api/v1/conversations/:id/messages (user role + audio) →
//      persists the user turn so it survives reload
//   6. POST /api/v1/ai/messages (SSE) → stream the assistant reply.
//      AS each sentence completes during the stream, fire a TTS request
//      in parallel and push it onto an in-order playback queue, so the
//      first audio reaches the user within ~1s of the LLM's first token.
//   7. POST /api/v1/conversations/:id/messages (assistant role + stitched mp3)
//      so the per-message replay button can serve from disk forever.
//   8. Replay buttons prefer the in-memory blob, fall back to the
//      persisted server blob, and only as a last resort re-bill TTS.
//
// On mount we hydrate the persisted thread for the current user (or
// create a new conversation if none exists yet) so reloading the page
// brings the entire history back, including audio.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ApiError, apiFetch, streamAiMessages, translateText } from '../lib/api'
import { useMe, useSttFixtures, useStudyMaterial } from '../lib/queries'
import { useUserStore } from '../lib/userStore'
import { useVoiceRecorder } from '../lib/useVoiceRecorder'
import { AudioQueue } from '../lib/audioQueue'
import { SentenceSplitter } from '../lib/sentences'
import { fetchTtsWithFallback, getCachedAudio, rememberAudio } from '../lib/ttsCache'
import {
  appendMessage,
  createConversation,
  fetchMessageAudio,
  getConversation,
} from '../lib/conversations'
import { LoadingScreen } from '../components/LoadingScreen'
import type { ConversationMessage, SttFixture } from '../lib/types'

const DEFAULT_GREETING = "Hi! I'm Ringle, your English speaking partner. What's your name and what do you do?"

// Module-level dedup so the canned opener plays exactly once per
// conversation, even when React 18 StrictMode mounts the page twice
// in dev (which would otherwise reset the per-instance useRef guard
// and re-fire the greeting effect — i.e. play the audio twice).
//
// Keyed by conversationId because that's the unit we want to dedup
// on: if the user wipes their conversation and a fresh one is
// created, that new id has never been greeted and the opener
// rightly plays again.
const greetedConversationIds = new Set<number>()
// StrictMode runs effects twice → two concurrent ensureConversation
// calls → two createConversation API calls → two different IDs →
// greetedConversationIds can't dedup by ID alone. This module-level
// flag prevents the second call from entering the async path at all.
let ensureInFlight = false

type Turn = {
  // Server-assigned message id once the row exists; null only for the
  // canned greeting (which we never persist) and the in-flight assistant
  // bubble before the stream finishes.
  id: string
  role: 'user' | 'assistant'
  text: string
  pending?: boolean
  audioPath?: string | null
}

const turnKey = (id: string) => `turn:${id}`

export function ConversationPage() {
  // /me poll lives in the RequireAccess wrapper at the route level; reading
  // the cached query here is cheap and reflects the same data.
  useMe()
  const recorder = useVoiceRecorder()
  // ?study=:id pulls the cached curriculum row that should prime the
  // assistant's system prompt for this whole session. The first turn's
  // greeting also comes from the material's example dialogue when present.
  const [searchParams] = useSearchParams()
  const studyIdParam = searchParams.get('study')
  const studyId = studyIdParam ? Number(studyIdParam) : null
  const studyQuery = useStudyMaterial(studyId)
  // Office-mode demo fixtures. Three pre-seeded WAVs that the backend
  // already has hashed in stt_artifacts; clicking one substitutes for
  // the microphone capture step entirely.
  const fixtures = useSttFixtures()
  const [turns, setTurns] = useState<Turn[]>([])
  const [status, setStatus] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [conversationId, setConversationId] = useState<number | null>(null)
  // Explicit init state machine. The page renders one of three things:
  //   loading → spinner   (waiting on /me → conversation hydrate → study)
  //   error   → retry card (any of the bootstraps threw)
  //   ready   → conversation UI
  // Tracking this explicitly avoids the old "permanent spinner" trap
  // where a hydration failure left hydrated=false / conversationId=null
  // with no visible error.
  const [initState, setInitState] = useState<'loading' | 'error' | 'ready'>('loading')
  const [initError, setInitError] = useState<string | null>(null)
  const greetingPlayed = useRef(false)
  const threadRef = useRef<HTMLDivElement>(null)
  const queue = useMemo(() => new AudioQueue(), [])
  const meQuery = useMe()
  const meFeatures = meQuery.data?.features

  const persistedConversationId = useUserStore((s) => s.getConversationForCurrentUser())
  const setConversationForCurrentUser = useUserStore((s) => s.setConversationForCurrentUser)
  const userId = useUserStore((s) => s.currentUserId)

  // Hydrate (or create) the user's conversation. Re-runs when the active
  // user changes or talk feature toggles on. Always lands on either
  // initState='ready' (with conversationId set) or initState='error'
  // — never leaves the page stuck in a half-initialised limbo.
  const ensureConversation = useCallback(async () => {
    if (meFeatures === undefined) return
    if (ensureInFlight) return
    if (!meFeatures.includes('talk')) {
      setInitState('error')
      setInitError('Talk 멤버십이 없어요.')
      return
    }
    ensureInFlight = true
    setInitState('loading')
    setInitError(null)
    try {
      let id = persistedConversationId
      let messages: ConversationMessage[] = []
      if (id !== null) {
        try {
          const fetched = await getConversation(id)
          messages = fetched.messages ?? []
        } catch (e) {
          if (e instanceof ApiError && e.status === 404) {
            id = null
          } else {
            throw e
          }
        }
      }
      if (id === null) {
        const created = await createConversation()
        id = created.id
        messages = created.messages ?? []
        setConversationForCurrentUser(id)
      }
      setConversationId(id)
      setTurns(
        messages.map((m) => ({
          id: turnKey(String(m.id)),
          role: m.role,
          text: m.text,
          audioPath: m.audio_url,
        })),
      )
      greetingPlayed.current = false
      setInitState('ready')
    } catch (e) {
      setInitError(formatError(e))
      setInitState('error')
    } finally {
      ensureInFlight = false
    }
  }, [meFeatures, persistedConversationId, setConversationForCurrentUser])

  useEffect(() => {
    void ensureConversation()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId, meFeatures?.join(',')])

  useEffect(() => {
    return () => queue.stop()
  }, [queue])

  useEffect(() => {
    threadRef.current?.scrollTo({ top: threadRef.current.scrollHeight, behavior: 'smooth' })
  }, [turns])

  // Speak the canned opener exactly once per fresh conversation.
  //
  // Idempotency lives in the module-level greetedConversationIds set
  // (NOT a per-component ref) so that React 18 StrictMode's mount →
  // unmount → mount dance in development cannot fire the greeting
  // twice. The previous useRef guard was reset between StrictMode
  // mounts, which is exactly the "재생이 2번 되거든" symptom.
  //
  // We also wait until:
  //   - bootstrap is ready (conversation hydrated, id known)
  //   - turns are empty (i.e. fresh thread, not a restored history)
  //   - if /study?study=:id was supplied, the study material query has
  //     settled (data OR error). On error we fall back to the default
  //     greeting instead of waiting forever.
  useEffect(() => {
    if (initState !== 'ready') return
    if (conversationId === null) return
    if (greetedConversationIds.has(conversationId)) return
    if (turns.length > 0) return
    if (studyId !== null && studyQuery.isLoading) return

    greetedConversationIds.add(conversationId)
    greetingPlayed.current = true
    const id = turnKey('greeting')
    const greetingText =
      studyQuery.data?.example_dialogue.find((d) => d.role === 'assistant')?.text ??
      DEFAULT_GREETING
    setTurns([{ id, role: 'assistant', text: greetingText }])
    queue.reset()
    queue.enqueue(
      fetchTtsWithFallback(greetingText).then((blob) => {
        if (blob) rememberAudio(id, blob)
        return blob
      }),
    )
  }, [initState, conversationId, turns.length, studyId, studyQuery.isLoading, studyQuery.data, queue])

  // ─── Render gate ─────────────────────────────────────────────────────
  // Bootstrap must finish before the conversation UI is allowed to mount.
  // Loading and error states render their own dedicated screens so the
  // user always sees *something* — not a half-rendered empty thread.
  if (initState === 'loading') {
    if (meQuery.isError) {
      return (
        <div className="card forbidden-card">
          <h2>사용자 정보를 불러오지 못했어요</h2>
          <p className="muted forbidden-card__body">
            서버에 연결할 수 없거나 인증이 만료됐을 수 있어요.
          </p>
          <div className="forbidden-card__cta">
            <button type="button" className="btn primary" onClick={() => meQuery.refetch()}>
              다시 시도
            </button>
          </div>
        </div>
      )
    }
    return <LoadingScreen message="대화를 불러오는 중…" />
  }
  if (initState === 'error') {
    return (
      <div className="card forbidden-card">
        <h2>대화를 불러오지 못했어요</h2>
        <p className="muted forbidden-card__body">{initError ?? '알 수 없는 오류가 발생했어요.'}</p>
        <div className="forbidden-card__cta">
          <button type="button" className="btn primary" onClick={() => void ensureConversation()}>
            다시 시도
          </button>
        </div>
      </div>
    )
  }

  const handleStart = async () => {
    setError(null)
    queue.stop()
    queue.reset()
    await recorder.start()
  }

  // Run the entire turn pipeline given an already-recorded WAV: STT,
  // persist user turn, stream assistant reply, persist it. Used by both
  // the live mic flow and the fixture-driven demo flow so they share
  // every line below the audio capture.
  //
  // The user turn is added to the thread *optimistically* — i.e. before
  // STT and the persist round-trip finish — so the recruiter sees their
  // bubble appear immediately even when the STT cache misses and Gemini
  // is in flight. We cache the in-memory wav under the placeholder id so
  // the replay button works the instant the bubble appears, then we
  // promote the id to the canonical server id once persist completes.
  const runTurn = async (wav: Blob) => {
    if (conversationId === null) return

    const userPlaceholderId = turnKey(`pending-user-${crypto.randomUUID()}`)
    rememberAudio(userPlaceholderId, wav)
    setTurns((prev) => [
      ...prev,
      { id: userPlaceholderId, role: 'user', text: '음성을 텍스트로 바꾸는 중…', pending: true },
    ])
    setStatus('Transcribing…')

    const fd = new FormData()
    fd.append('audio', wav, 'speech.wav')
    const stt = await apiFetch<{ text: string; cache?: string }>(
      '/api/v1/ai/transcriptions',
      { method: 'POST', formData: fd },
    )
    const sttText = stt.text
    const sttCacheStatus = stt.cache

    setTurns((prev) =>
      prev.map((t) =>
        t.id === userPlaceholderId ? { ...t, text: sttText, pending: true } : t,
      ),
    )

    // (4) Persist (text + wav). Server returns the canonical id; we
    // promote the bubble and transfer the cached blob over.
    const persistedUser = await appendMessage({
      conversationId,
      role: 'user',
      text: sttText,
      audio: wav,
      audioFilename: 'speech.wav',
    })
    const userTurnId = turnKey(String(persistedUser.id))
    rememberAudio(userTurnId, wav)
    setTurns((prev) =>
      prev.map((t) =>
        t.id === userPlaceholderId
          ? {
              id: userTurnId,
              role: 'user',
              text: persistedUser.text,
              audioPath: persistedUser.audio_url,
            }
          : t,
      ),
    )
    const userTurn: Turn = {
      id: userTurnId,
      role: 'user',
      text: persistedUser.text,
      audioPath: persistedUser.audio_url,
    }

    const assistantPlaceholderId = turnKey(`pending-${crypto.randomUUID()}`)
    setTurns((prev) => [
      ...prev,
      { id: assistantPlaceholderId, role: 'assistant', text: '', pending: true },
    ])

    setStatus(sttCacheStatus === 'hit' ? 'Thinking… (STT cache hit)' : 'Thinking…')
    const history = [...turns, userTurn].map((t) => ({ role: t.role, text: t.text }))

    // Stream LLM tokens; whenever a sentence completes we kick off TTS
    // for it in parallel and let AudioQueue play them back in order.
    queue.reset()
    const splitter = new SentenceSplitter()
    const sentenceBlobs: Promise<Blob>[] = []
    let acc = ''

    await streamAiMessages(
      history,
      (delta) => {
        acc += delta
        setTurns((prev) =>
          prev.map((t) => (t.id === assistantPlaceholderId ? { ...t, text: acc } : t)),
        )
        for (const sentence of splitter.feed(delta)) {
          const p = fetchTtsWithFallback(sentence).then((b) => b ?? new Blob())
          sentenceBlobs.push(p)
          queue.enqueue(p)
        }
      },
      { studyMaterialId: studyId ?? undefined, conversationId: conversationId ?? undefined },
    )

    const tail = splitter.flush()
    if (tail) {
      const p = fetchTtsWithFallback(tail).then((b) => b ?? new Blob())
      sentenceBlobs.push(p)
      queue.enqueue(p)
    }

    // Guard: if the LLM stream ended without any content (Gemini quota
    // exhausted, network blip, etc.) we must NOT persist an empty
    // assistant turn — the messages controller rejects blank text and
    // would 400 the entire turn pipeline. Drop the placeholder, surface
    // the failure, and let the user retry.
    if (acc.trim().length === 0) {
      setTurns((prev) => prev.filter((t) => t.id !== assistantPlaceholderId))
      throw new Error('AI 응답이 비어있어요. 잠시 후 다시 시도해주세요.')
    }

    // Stitch all the per-sentence blobs into one mp3 + persist it,
    // then swap the placeholder for the canonical server-assigned id
    // so replays go through the cached server blob too.
    const stitched = await Promise.all(sentenceBlobs).then((blobs) => {
      return blobs.length > 0 ? new Blob(blobs, { type: 'audio/mpeg' }) : undefined
    })
    const persistedAssistant = await appendMessage({
      conversationId,
      role: 'assistant',
      text: acc,
      audio: stitched,
      audioFilename: 'reply.mp3',
    })
    const finalAssistantId = turnKey(String(persistedAssistant.id))
    if (stitched) rememberAudio(finalAssistantId, stitched)

    setTurns((prev) =>
      prev.map((t) =>
        t.id === assistantPlaceholderId
          ? {
              id: finalAssistantId,
              role: 'assistant',
              text: persistedAssistant.text,
              audioPath: persistedAssistant.audio_url,
            }
          : t,
      ),
    )
    setStatus('')
  }

  const handleSubmit = async () => {
    if (busy || conversationId === null) return
    setBusy(true)
    try {
      const wav = await recorder.finalize()
      if (!wav) {
        setStatus('')
        setError('음성을 감지하지 못했어요. 마이크에 가깝게, 조금 더 길게 말해보세요.')
        setBusy(false)
        return
      }
      await runTurn(wav)
    } catch (e: unknown) {
      setError(formatError(e))
      setStatus('')
    } finally {
      setBusy(false)
    }
  }

  // Office mode: synthesise the fixture text via TTS so the recruiter
  // hears natural speech, then send the SAME bytes through STT so the
  // dev-mode example actually exercises the recognition path. First
  // call hits Gemini and caches the artifact; subsequent calls hit
  // the lazy `stt_artifacts` cache.
  const handleFixture = async (fixture: SttFixture) => {
    if (busy || conversationId === null) return
    setBusy(true)
    setError(null)
    try {
      setStatus('Generating speech…')
      const blob = await fetchTtsWithFallback(fixture.text)
      if (!blob) throw new Error('TTS 음성을 생성하지 못했어요.')
      const wav = await recorder.simulate(blob)
      await runTurn(wav)
    } catch (e: unknown) {
      setError(formatError(e))
      setStatus('')
    } finally {
      setBusy(false)
    }
  }

  // Replay always reads from cache. Either tier counts:
  //   1. in-memory blob (same session)             ── 0 network
  //   2. persisted server blob via audio_url       ── 1 cheap GET, no AI bill
  //
  // We never re-synthesise via TTS on replay anymore: the audio for any
  // bubble we render has already been fetched at least once during the
  // turn pipeline (TTS during streaming, or the user's mic capture), so
  // it must already exist in one of these two caches. The replay button
  // is gated by `canReplay` below to match.
  const handleReplay = async (turn: Turn) => {
    queue.stop()
    queue.reset()

    const cached = getCachedAudio(turn.id)
    if (cached) {
      queue.enqueue(Promise.resolve(cached))
      return
    }
    if (turn.audioPath) {
      try {
        const blob = await fetchMessageAudio(turn.audioPath)
        rememberAudio(turn.id, blob)
        queue.enqueue(Promise.resolve(blob))
      } catch {
        // The cached server blob is gone (DB wipe / Active Storage GC).
        // Surface a soft error rather than silently re-billing TTS.
        setError('이 메시지의 저장된 음성을 찾지 못했어요.')
      }
    }
  }

  const recording = recorder.state === 'recording' || recorder.state === 'starting'

  return (
    <div className="conv page-enter">
      <div className="conv-thread" ref={threadRef}>
        {turns.length === 0 && <div className="empty-state">Loading conversation…</div>}
        {turns.map((t) => (
          <ChatBubble key={t.id} turn={t} onReplay={handleReplay} />
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
            {recorder.idlePrompt ? (
              <div className="idle-prompt">
                <p>음성이 감지되지 않습니다. 지금까지 녹음된 내용을 보낼까요?</p>
                <div className="idle-prompt__actions">
                  <button className="btn ghost" onClick={() => { recorder.dismissIdlePrompt(); recorder.cancel() }}>
                    취소
                  </button>
                  <button className="btn primary" onClick={() => { recorder.dismissIdlePrompt(); handleSubmit() }} disabled={busy}>
                    보내기
                  </button>
                </div>
              </div>
            ) : (
              <div className="mic-row">
                <button className="btn ghost" onClick={recorder.cancel}>
                  취소
                </button>
                <button className="btn primary big" onClick={handleSubmit} disabled={busy}>
                  답변 완료
                </button>
              </div>
            )}
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

            {fixtures.data && fixtures.data.length > 0 && (
              <FixturePicker
                fixtures={fixtures.data}
                disabled={busy}
                onPick={handleFixture}
              />
            )}
          </>
        )}
      </div>
    </div>
  )
}

// Office-mode picker. Each button plays the seeded WAV through the
// recorder's simulate() path so the recruiter sees the same waveform
// animation a real mic capture would produce, then submits to STT
// where the Stt::Transcribe cache hits.
function FixturePicker({
  fixtures,
  disabled,
  onPick,
}: {
  fixtures: SttFixture[]
  disabled: boolean
  onPick: (f: SttFixture) => void
}) {
  return (
    <div className="fixture-picker">
      <div className="fixture-picker__head">
        <span className="muted">마이크 대신 예문 사용 (STT 캐시 hit)</span>
      </div>
      <div className="fixture-picker__row">
        {fixtures.map((f) => (
          <button
            key={f.slug}
            type="button"
            className="btn fixture-picker__item"
            onClick={() => onPick(f)}
            disabled={disabled}
            title={f.text}
          >
            <span className="fixture-picker__label">{f.label}</span>
            <span className="fixture-picker__text">{f.text}</span>
          </button>
        ))}
      </div>
    </div>
  )
}

const translationCache = new Map<string, string>()

function ChatBubble({ turn, onReplay }: { turn: Turn; onReplay: (t: Turn) => void }) {
  const [showTranslation, setShowTranslation] = useState(false)
  const [translation, setTranslation] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const canReplay =
    !turn.pending &&
    turn.text.length > 0 &&
    (getCachedAudio(turn.id) !== undefined || !!turn.audioPath)

  const canTranslate = turn.role === 'assistant' && !turn.pending && turn.text.length > 0

  const handleToggle = async () => {
    if (showTranslation) {
      setShowTranslation(false)
      return
    }
    const cached = translationCache.get(turn.text)
    if (cached) {
      setTranslation(cached)
      setShowTranslation(true)
      return
    }
    setLoading(true)
    try {
      const result = await translateText(turn.text)
      translationCache.set(turn.text, result)
      setTranslation(result)
      setShowTranslation(true)
    } catch {
      setTranslation('번역을 불러오지 못했어요.')
      setShowTranslation(true)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className={`bubble ${turn.role}`}>
      <div className="bubble__content">
        <div className="text">
          {turn.text}
          {turn.pending && <span className="dot-pulse" aria-hidden />}
        </div>
        {showTranslation && translation && (
          <div className="bubble__translation">{translation}</div>
        )}
      </div>
      <div className="bubble__actions">
        {canReplay && (
          <button className="replay" aria-label="Replay" onClick={() => onReplay(turn)}>▶</button>
        )}
        {canTranslate && (
          <button
            className="bubble__translate-btn"
            onClick={handleToggle}
            disabled={loading}
          >
            {loading ? '…' : showTranslation ? '접기' : '번역'}
          </button>
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
