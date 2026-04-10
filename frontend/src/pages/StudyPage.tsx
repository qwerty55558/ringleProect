// /study — cached AI curriculum.
//
// The list on the left is fetched from /api/v1/study_materials (a server
// cache populated by `StudyMaterials::CurriculumSeed` plus any rows the
// Generate service has added). The pool is global: every successful
// generation is cached forever and surfaces in everyone else's list,
// so a Basic learner who burns their 3 personal generation slots is
// also rotating through topics OTHER users paid to create.
//
// Two action paths from the detail panel:
//
//   - "핵심 표현 듣기" (default for any study learner) — plays TTS for
//     each key expression in order via the same /api/v1/ai/speech
//     endpoint the conversation page uses. Backed by the global TTS
//     cache so identical phrases never re-bill ElevenLabs.
//
//   - "AI 와 대화로 학습 시작" (talk-feature-only) — pushes the learner
//     into /conversation?study=:id so the assistant's system prompt is
//     primed with this curriculum. Hidden when the user lacks `talk`,
//     because the conversation page would just bounce them.

import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ApiError } from '../lib/api'
import { useGenerateStudyMaterial, useMe, useStudyMaterials } from '../lib/queries'
import { fetchTtsWithFallback } from '../lib/ttsCache'
import { toSpeakable } from '../lib/speakable'
import { AudioQueue } from '../lib/audioQueue'
import { useUserStore } from '../lib/userStore'
import { appendMessage, createConversation } from '../lib/conversations'
import type { StudyMaterial } from '../lib/types'

const LEVEL_LABEL: Record<string, string> = {
  novice: '입문',
  beginner: '초급',
  intermediate: '중급',
  advanced: '고급',
}

const CATEGORY_LABEL: Record<string, string> = {
  daily: '일상',
  business: '비즈니스',
  travel: '여행',
  hobby: '취미',
  academic: '학술',
  conversation: '회화',
}

export function StudyPage() {
  const me = useMe()
  const list = useStudyMaterials()
  const generate = useGenerateStudyMaterial()
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [topicInput, setTopicInput] = useState('')

  const seeded = list.data?.seeded ?? []
  const aiGenerated = list.data?.ai_generated ?? []
  const allMaterials = [...seeded, ...aiGenerated]
  const selected =
    allMaterials.find((m) => m.id === selectedId) ?? allMaterials[0] ?? null

  // Cap meta from /me. The backend is the authoritative gate, but we
  // mirror it here so the input disables before the user can fire a
  // wasted request.
  const generations = me.data?.study_generations
  const remaining = generations?.remaining ?? 0
  const limit = generations?.limit ?? 3
  const capReached = remaining <= 0

  const hasTalk = me.data?.features.includes('talk') ?? false

  const handleGenerate = async () => {
    const topic = topicInput.trim()
    if (!topic || capReached) return
    try {
      const created = await generate.mutateAsync(topic)
      setTopicInput('')
      setSelectedId(created.id)
    } catch {
      // surfaced via generate.error below
    }
  }

  return (
    <div className="study page-enter">
      <aside className="study__list">
        <div className="section-header">
          <h2>학습 커리큘럼</h2>
          <button
            type="button"
            className="btn ghost small"
            onClick={() => list.refetch()}
            disabled={list.isFetching}
            title="새 로테이션 가져오기"
          >
            {list.isFetching ? '새로고침 중…' : '↻ 새로고침'}
          </button>
        </div>

        {list.isLoading && <p className="muted">불러오는 중…</p>}

        {seeded.length > 0 && (
          <>
            <div className="study__group-label">기본 커리큘럼</div>
            <ul className="study__items">
              {seeded.map((m, i) => (
                <li key={m.id} className="stagger-item" style={{ '--i': i } as React.CSSProperties}>
                  <button
                    type="button"
                    className={`study__item ${selected?.id === m.id ? 'is-selected' : ''}`}
                    onClick={() => setSelectedId(m.id)}
                  >
                    <div className="study__item-title">{m.title}</div>
                    <div className="study__item-meta">
                      {LEVEL_LABEL[m.level] ?? m.level} · {CATEGORY_LABEL[m.category] ?? m.category}
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          </>
        )}

        <div className="study__group-label">AI 생성 토픽</div>
        {aiGenerated.length === 0 ? (
          <p className="study__empty-note">아직 생성된 AI 토픽이 없어요.</p>
        ) : (
          <ul className="study__items">
            {aiGenerated.map((m, i) => (
              <li key={m.id} className="stagger-item" style={{ '--i': i } as React.CSSProperties}>
                <button
                  type="button"
                  className={`study__item ${selected?.id === m.id ? 'is-selected' : ''}`}
                  onClick={() => setSelectedId(m.id)}
                >
                  <div className="study__item-title">{m.title}</div>
                  <div className="study__item-meta">
                    {LEVEL_LABEL[m.level] ?? m.level} · {CATEGORY_LABEL[m.category] ?? m.category}
                    <span className="study__ai-tag">AI</span>
                  </div>
                </button>
              </li>
            ))}
          </ul>
        )}

        <div className="study__generate">
          <div className="study__generate-head">
            <label className="muted">새 토픽 생성 (AI)</label>
            <span className={`study__generate-quota ${capReached ? 'is-empty' : ''}`}>
              남은 횟수 {remaining}/{limit}
            </span>
          </div>
          <div className="study__generate-row">
            <input
              type="text"
              placeholder={capReached ? '생성 가능 횟수를 모두 사용했어요' : '예: negotiating salary'}
              value={topicInput}
              onChange={(e) => setTopicInput(e.target.value)}
              disabled={capReached}
            />
            <button
              className="btn primary"
              onClick={handleGenerate}
              disabled={generate.isPending || capReached || topicInput.trim().length === 0}
            >
              {generate.isPending ? '생성 중…' : '생성'}
            </button>
          </div>
          {capReached && (
            <p className="muted study__generate-hint">
              생성한 토픽은 이미 다른 학습자들과 공유되고 있어요. 위 목록에서
              더 많은 캐싱된 토픽을 둘러보세요.
            </p>
          )}
          {generate.error && (
            <p className="error-banner">{generateErrorMessage(generate.error, limit)}</p>
          )}
        </div>
      </aside>

      <section className="study__detail">
        {selected ? (
          <StudyDetail material={selected} hasTalk={hasTalk} />
        ) : (
          <div className="empty-state">왼쪽 목록에서 학습 토픽을 선택하세요.</div>
        )}
      </section>
    </div>
  )
}

function generateErrorMessage(err: unknown, limit: number): string {
  if (err instanceof ApiError) {
    if (err.status === 422) {
      const body = err.body as { error?: string; used?: number } | null
      if (body?.error === 'generation_limit_reached') {
        return `생성 가능 횟수를 모두 사용했어요 (${body.used ?? limit}/${limit}).`
      }
      if (body?.error === 'inappropriate_content') {
        return '부적절한 표현이 포함되어 있어 생성할 수 없어요. 다른 주제로 시도해보세요.'
      }
    }
    if (err.status === 502) return 'AI 서비스가 일시적으로 응답하지 않습니다.'
  }
  return `생성 실패: ${(err as Error).message}`
}

// Detail card. Owns its own AudioQueue so playback state for the
// 핵심 표현 듣기 button is local — switching to a different topic
// or unmounting the page stops whatever is playing.
function StudyDetail({ material, hasTalk }: { material: StudyMaterial; hasTalk: boolean }) {
  const queueRef = useRef(AudioQueue.shared())
  const [playState, setPlayState] = useState<'idle' | 'playing'>('idle')

  // Cancel any in-flight playback when the user switches topics OR
  // navigates away. The AudioQueue resets `cancelled` so the next
  // press starts a fresh sequence.
  useEffect(() => {
    return () => queueRef.current?.stop()
  }, [material.id])

  const playKeyExpressions = async () => {
    const queue = queueRef.current!
    queue.reset()
    setPlayState('playing')
    for (const expr of material.key_expressions) {
      queue.enqueue(fetchTtsWithFallback(toSpeakable(expr)))
    }
    // Crude completion detection — wait until the queue empties.
    // The AudioQueue doesn't expose a "done" signal so we poll its
    // private state via a setTimeout chain.
    const tick = () => {
      // Re-checking via a microtask is fine because the queue's
      // playing flag flips false synchronously after the last clip.
      const stillPlaying = (queue as unknown as { playing: boolean }).playing
      if (stillPlaying) setTimeout(tick, 250)
      else setPlayState('idle')
    }
    setTimeout(tick, 250)
  }

  const stopPlayback = () => {
    queueRef.current?.reset()
    setPlayState('idle')
  }

  return (
    <div className="card study__card">
      <div className="study__detail-head">
        <h2>{material.title}</h2>
        <div className="muted">
          {LEVEL_LABEL[material.level] ?? material.level} ·{' '}
          {CATEGORY_LABEL[material.category] ?? material.category}
          {material.ai_generated && <span className="study__ai-tag">AI 생성</span>}
        </div>
      </div>
      <p>{material.description}</p>

      <h3>핵심 표현</h3>
      <ul className="study__expressions">
        {material.key_expressions.map((expr, i) => (
          <li key={i}>{expr}</li>
        ))}
      </ul>

      <h3>예시 대화</h3>
      <div className="study__example">
        {material.example_dialogue.map((line, i) => (
          <div key={i} className={`bubble ${line.role}`}>
            <div className="text">{line.text}</div>
          </div>
        ))}
      </div>

      <div className="study__cta-row">
        {playState === 'playing' ? (
          <button type="button" className="btn ghost big" onClick={stopPlayback}>
            ■ 재생 중지
          </button>
        ) : (
          <button type="button" className="btn primary big" onClick={playKeyExpressions}>
            ▶ 핵심 표현 듣기
          </button>
        )}
        {hasTalk && (
          <StartConversationButton material={material} />
        )}
      </div>
    </div>
  )
}

function StartConversationButton({ material }: { material: StudyMaterial }) {
  const navigate = useNavigate()
  const existingId = useUserStore((s) => s.getConversationForCurrentUser())
  const setConversation = useUserStore((s) => s.setConversationForCurrentUser)

  const handleClick = async () => {
    if (existingId) {
      const ok = window.confirm('진행 중인 대화를 종료하고 새 학습을 시작할까요?')
      if (!ok) return
    } else {
      const ok = window.confirm('이 커리큘럼으로 AI 대화를 시작할까요?')
      if (!ok) return
    }
    const firstQuestion =
      material.example_dialogue.find((d) => d.role === 'assistant')?.text ??
      `안녕하세요! "${material.title}" 주제로 대화를 시작해볼게요.`
    const created = await createConversation({ title: material.title, studyMaterialId: material.id })
    const ttsBlob = await fetchTtsWithFallback(toSpeakable(firstQuestion))
    await appendMessage({
      conversationId: created.id,
      role: 'assistant',
      text: firstQuestion,
      audio: ttsBlob ?? undefined,
      audioFilename: 'greeting.mp3',
    })
    setConversation(created.id)
    navigate(`/conversation?study=${material.id}`)
  }

  return (
    <button type="button" className="btn ghost big" onClick={handleClick}>
      AI 와 대화로 학습 시작 →
    </button>
  )
}
