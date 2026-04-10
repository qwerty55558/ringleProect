import { useCallback, useEffect, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useMe, useConversations, queryKeys } from '../lib/queries'
import { apiFetch } from '../lib/api'
import { deleteConversation } from '../lib/conversations'
import { useUserStore } from '../lib/userStore'
import { useAnalysisStream } from '../lib/useAnalysisStream'
import type { Conversation, AnalysisResult } from '../lib/types'
import { formatServerDate, formatServerTime } from '../lib/serverTime'

type Phase = 'loading' | 'idle' | 'polling' | 'done' | 'error'

const LEVEL_LABEL: Record<string, string> = {
  novice: '입문',
  beginner: '초급',
  intermediate: '중급',
  advanced: '고급',
}



function stripFence(raw: string): string {
  return raw.replace(/^```json?\n?/, '').replace(/\n?```$/, '')
}

type AnalysisResponse = {
  status: 'none' | 'pending' | 'completed' | 'failed'
  result: string | null
  analyzed_at?: string
  cooldown_remaining: number
}

function tryParse(raw: string): { result: AnalysisResult | null; error: boolean; rawText: string } {
  const stripped = stripFence(raw.trim())
  try {
    return { result: JSON.parse(stripped), error: false, rawText: raw }
  } catch {
    return { result: null, error: true, rawText: raw }
  }
}

export function AnalysisPage() {
  useMe()
  const conversations = useConversations()
  const qc = useQueryClient()
  const setConversationForCurrentUser = useUserStore((s) => s.setConversationForCurrentUser)

  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [phase, setPhase] = useState<Phase>('idle')
  const [result, setResult] = useState<AnalysisResult | null>(null)
  const [parseError, setParseError] = useState(false)
  const [rawText, setRawText] = useState('')
  const [errorMessage, setErrorMessage] = useState('')
  const [cooldown, setCooldown] = useState(0)
  const [analyzedAt, setAnalyzedAt] = useState<string | null>(null)
  const pendingConvRef = useRef<number | null>(null)

  const list: Conversation[] = conversations.data ?? []
  const selected = list.find((c) => c.id === selectedId) ?? null
  const messageCount = selected?.message_count ?? 0

  const cleanup = () => {
    pendingConvRef.current = null
  }

  const applyResult = (data: AnalysisResponse) => {
    if (data.result) {
      const parsed = tryParse(data.result)
      setResult(parsed.result)
      setParseError(parsed.error)
      setRawText(parsed.rawText)
    }
    setCooldown(data.cooldown_remaining)
    if (data.analyzed_at) setAnalyzedAt(data.analyzed_at)
  }

  // SSE changed 이벤트 수신 시 — 분석 완료/실패를 감지
  const handleAnalysisChanged = useCallback(async () => {
    const convId = pendingConvRef.current
    if (convId === null) return
    try {
      const data = await apiFetch<AnalysisResponse>('/api/v1/ai/analysis', {
        query: { conversation_id: convId },
      })
      if (data.status === 'completed') {
        pendingConvRef.current = null
        applyResult(data)
        setPhase('done')
      } else if (data.status === 'failed') {
        pendingConvRef.current = null
        setErrorMessage('분석에 실패했어요. 다시 시도해주세요.')
        setPhase('error')
      }
    } catch {
      // ignore — next SSE event will retry
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useAnalysisStream(handleAnalysisChanged)

  // 대화 선택 시 저장된 분석 로드
  useEffect(() => {
    if (selectedId === null) return
    let cancelled = false

    const load = async () => {
      setPhase('loading')
      setResult(null)
      setParseError(false)
      setErrorMessage('')
      setRawText('')
      setCooldown(0)
      setAnalyzedAt(null)
      cleanup()

      try {
        const data = await apiFetch<AnalysisResponse>('/api/v1/ai/analysis', {
          query: { conversation_id: selectedId },
        })
        if (cancelled) return

        if (data.status === 'completed' && data.result) {
          applyResult(data)
          setPhase('done')
        } else if (data.status === 'pending') {
          pendingConvRef.current = selectedId
          setPhase('polling')
        } else {
          setPhase('idle')
        }
      } catch {
        if (!cancelled) setPhase('idle')
      }
    }

    void load()
    return () => { cancelled = true; cleanup() }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId])

  useEffect(() => {
    if (cooldown <= 0) return
    const timer = setInterval(() => {
      setCooldown((prev) => { if (prev <= 1) { clearInterval(timer); return 0 }; return prev - 1 })
    }, 1000)
    return () => clearInterval(timer)
  }, [cooldown])

  useEffect(() => () => cleanup(), [])

  const handleDeleteAll = async () => {
    if (!window.confirm('모든 대화 기록을 삭제할까요? 분석 결과도 함께 삭제됩니다.')) return
    try {
      const result = await apiFetch<{ deleted: number }>('/api/v1/conversations/all', { method: 'DELETE' })
      setConversationForCurrentUser(null)
      setSelectedId(null)
      setPhase('idle')
      setResult(null)
      cleanup()
      qc.invalidateQueries({ queryKey: queryKeys.conversations })
      window.alert(`${result.deleted}개의 대화를 삭제했어요.`)
    } catch (e) {
      window.alert(`삭제 실패: ${(e as Error).message}`)
    }
  }

  const handleSelect = (conv: Conversation) => {
    cleanup()
    setSelectedId(conv.id)
  }

  const handleStart = async () => {
    if (!selected || phase === 'polling' || cooldown > 0) return

    setPhase('polling')
    setResult(null)
    setParseError(false)
    setErrorMessage('')
    setRawText('')
    pendingConvRef.current = selected.id

    try {
      await apiFetch('/api/v1/ai/analysis', {
        method: 'POST',
        body: { conversation_id: selected.id },
      })
      // 백그라운드 실행 시작됨 — SSE changed 이벤트 대기
    } catch (err: unknown) {
      setErrorMessage(err instanceof Error ? err.message : '분석 요청에 실패했어요.')
      setPhase('error')
      pendingConvRef.current = null
    }
  }

  const handleDeleteConversation = async (conv: Conversation) => {
    if (!window.confirm(`"${conv.title ?? `대화 #${conv.id}`}" 대화를 삭제할까요?`)) return
    try {
      await deleteConversation(conv.id)
      const currentConvId = useUserStore.getState().getConversationForCurrentUser()
      if (currentConvId === conv.id) setConversationForCurrentUser(null)
      qc.invalidateQueries({ queryKey: queryKeys.conversations })
      if (selectedId === conv.id) {
        setSelectedId(null)
        setPhase('idle')
        setResult(null)
        cleanup()
      }
    } catch (e) {
      window.alert(`삭제 실패: ${(e as Error).message}`)
    }
  }

  const busy = phase === 'polling'
  const canAnalyze = messageCount >= 2 && !busy && cooldown <= 0
  const buttonLabel = busy
    ? '분석 중…'
    : cooldown > 0
      ? `다시 분석 (${cooldown}초 후)`
      : result ? '다시 분석' : '분석 시작'

  return (
    <div className="analysis page-enter">
      <aside className="analysis__sidebar">
        <div className="section-header"><h2>대화 기록</h2></div>

        {conversations.isLoading && <p className="muted">불러오는 중…</p>}
        {!conversations.isLoading && list.length === 0 && (
          <p className="muted">분석할 대화 기록이 없어요.</p>
        )}
        <ul className="analysis__conv-list">
          {list.map((conv) => (
            <li key={conv.id}>
              <div className={`analysis__conv-item ${selectedId === conv.id ? 'is-selected' : ''}`}>
                <button
                  type="button"
                  className="analysis__conv-body"
                  onClick={() => handleSelect(conv)}
                >
                  <div className="analysis__conv-title">{conv.title ?? `대화 #${conv.id}`}</div>
                  <div className="analysis__conv-date muted">
                    {formatServerDate(conv.created_at)} · {conv.message_count ?? 0}개
                  </div>
                </button>
                <button
                  type="button"
                  className="analysis__conv-delete"
                  onClick={() => handleDeleteConversation(conv)}
                  title="대화 삭제"
                >
                  ×
                </button>
              </div>
            </li>
          ))}
        </ul>
        {list.length > 0 && (
          <button
            type="button"
            className="analysis__delete-all"
            onClick={handleDeleteAll}
          >
            모든 대화 기록 삭제
          </button>
        )}
      </aside>

      <section className="analysis__detail">
        {!selected && <div className="empty-state">왼쪽 목록에서 대화를 선택하세요.</div>}

        {selected && (
          <>
            <div className="analysis__detail-head">
              <div>
                <h2>{selected.title ?? `대화 #${selected.id}`}</h2>
                <p className="muted">
                  {formatServerDate(selected.created_at)} · 메시지 {messageCount}개
                  {analyzedAt && ` · 마지막 분석 ${formatServerTime(analyzedAt)}`}
                </p>
              </div>
              <button
                type="button"
                className="btn primary big"
                onClick={handleStart}
                disabled={!canAnalyze}
                title={messageCount < 2 ? '메시지가 2개 이상인 대화만 분석할 수 있어요' : undefined}
              >
                {buttonLabel}
              </button>
            </div>

            {phase === 'loading' && (
              <div className="analysis__streaming"><div className="spinner" /></div>
            )}

            {phase === 'polling' && (
              <div className="analysis__streaming">
                <div className="spinner" />
                <p className="muted">AI가 분석 중이에요…</p>
              </div>
            )}

            {phase === 'error' && (
              <div className="analysis__error">
                <p className="error-banner">{errorMessage}</p>
                <button type="button" className="btn ghost" onClick={handleStart}>다시 시도</button>
              </div>
            )}

            {phase === 'done' && parseError && (
              <div className="analysis__parse-error">
                <p className="error-banner">분석 결과를 파싱할 수 없어요.</p>
                <pre className="analysis__raw-text muted">{rawText}</pre>
              </div>
            )}

            {phase === 'idle' && <div className="empty-state">분석 시작 버튼을 눌러주세요.</div>}

            {phase === 'done' && result && !parseError && <AnalysisReport result={result} />}
          </>
        )}
      </section>
    </div>
  )
}

function ScoreBar({ score, label }: { score: number; label: string }) {
  const pct = Math.min(100, Math.max(0, score))
  return (
    <div className="analysis__score-row">
      <span className="analysis__score-name">{label}</span>
      <div className="analysis__score-track">
        <div className="analysis__score-bar" style={{ width: `${pct}%` }} role="progressbar"
          aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
          <span className="analysis__score-label">{pct}점</span>
        </div>
      </div>
    </div>
  )
}

function AnalysisReport({ result }: { result: AnalysisResult }) {
  return (
    <div className="analysis__report">
      <div className="analysis__level-row">
        <span className="analysis__level" data-level={result.overall_level}>
          {LEVEL_LABEL[result.overall_level] ?? result.overall_level}
        </span>
        <span className="muted">종합 레벨</span>
      </div>

      <div className="analysis__cards">
        <div className="card analysis__section">
          <ScoreBar score={result.grammar.score} label="문법" />
          {result.grammar.mistakes.length > 0 ? (
            <div className="analysis__table-wrap">
              <table className="analysis__table">
                <thead><tr><th>원문</th><th>수정</th><th>설명</th></tr></thead>
                <tbody>
                  {result.grammar.mistakes.map((m, i) => (
                    <tr key={i}>
                      <td className="analysis__original">{m.original}</td>
                      <td className="analysis__corrected">{m.corrected}</td>
                      <td>{m.explanation}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <p className="muted">문법 오류가 없어요.</p>}
        </div>

        <div className="card analysis__section">
          <ScoreBar score={result.vocabulary.score} label="어휘" />
          {result.vocabulary.frequent_words.length > 0 && (
            <div className="analysis__vocab-group">
              <h4 className="muted">자주 사용한 단어</h4>
              <ul className="analysis__word-list">
                {result.vocabulary.frequent_words.map((w, i) => (
                  <li key={i} className="analysis__word-chip">{w}</li>
                ))}
              </ul>
            </div>
          )}
          {result.vocabulary.alternatives.length > 0 && (
            <div className="analysis__vocab-group">
              <h4 className="muted">대체 표현 제안</h4>
              <ul className="analysis__alt-list">
                {result.vocabulary.alternatives.map((a, i) => (
                  <li key={i}>
                    <span className="analysis__used-word">{a.used}</span>
                    <span className="muted"> → </span>
                    {a.suggestions.map((s, j) => (
                      <span key={j} className="analysis__suggestion-chip">{s}</span>
                    ))}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>

        <div className="card analysis__section">
          <ScoreBar score={result.fluency.score} label="유창성" />
          <p>{result.fluency.comment}</p>
        </div>

        <div className="card analysis__section">
          <ScoreBar score={result.topic_relevance.score} label="주제 관련성" />
          <p>{result.topic_relevance.comment}</p>
        </div>

        {result.key_expressions && (
          <div className="card analysis__section">
            <h3>핵심 표현</h3>
            {result.key_expressions.used.length > 0 && (
              <div className="analysis__expr-group">
                <h4 className="muted">사용한 표현</h4>
                <ul className="analysis__word-list">
                  {result.key_expressions.used.map((e, i) => (
                    <li key={i} className="analysis__word-chip analysis__word-chip--used">{e}</li>
                  ))}
                </ul>
              </div>
            )}
            {result.key_expressions.missed.length > 0 && (
              <div className="analysis__expr-group">
                <h4 className="muted">놓친 표현</h4>
                <ul className="analysis__word-list">
                  {result.key_expressions.missed.map((e, i) => (
                    <li key={i} className="analysis__word-chip analysis__word-chip--missed">{e}</li>
                  ))}
                </ul>
              </div>
            )}
            {result.key_expressions.comment && <p>{result.key_expressions.comment}</p>}
          </div>
        )}

        {result.suggestions.length > 0 && (
          <div className="card analysis__section">
            <h3>개선 제안</h3>
            <ol className="analysis__suggestions">
              {result.suggestions.map((s, i) => <li key={i}>{s}</li>)}
            </ol>
          </div>
        )}
      </div>
    </div>
  )
}
