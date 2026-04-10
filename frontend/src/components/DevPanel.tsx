// Floating dev-tools widget. Bottom-right corner, click to expand a small
// panel with developer-only actions:
//
//   - Switch active account (the X-User-Id we forward to the API)
//   - Quick "← Admin" jump back to the seeded admin account
//   - Wipe every membership in the database
//   - Reset all browser-side state (localStorage / caches) and reload
//
// Rendered globally from App.tsx so it's available on every route.

import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../lib/api'
import { clearAudioCache } from '../lib/ttsCache'
import { deleteConversation } from '../lib/conversations'
import {
  useDeleteAiStudyMaterials,
  useResetStudyCurriculum,
  useResetStudyGenerationCounters,
  useTestCards,
} from '../lib/queries'
import { useUserStore, type RosterUser } from '../lib/userStore'

const FALLBACK_ROSTER: RosterUser[] = [
  { id: 1, name: 'Ringle Admin',  role: 'admin' },
  { id: 2, name: 'Danny Learner', role: 'user' },
  { id: 3, name: 'Alex Newcomer', role: 'user' },
]

export function DevPanel() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()
  const currentUserId = useUserStore((s) => s.currentUserId)
  const setCurrentUserId = useUserStore((s) => s.setCurrentUserId)
  const roster = useUserStore((s) => s.roster)
  const conversationId = useUserStore((s) => s.getConversationForCurrentUser())
  const setConversationForCurrentUser = useUserStore((s) => s.setConversationForCurrentUser)
  const selectedCardToken = useUserStore((s) => s.selectedCardToken)
  const setSelectedCardToken = useUserStore((s) => s.setSelectedCardToken)
  const testCards = useTestCards()

  const effectiveRoster = roster.length > 0 ? roster : FALLBACK_ROSTER
  const adminId = effectiveRoster.find((u) => u.role === 'admin')?.id ?? 1
  const isAdmin = currentUserId === adminId

  const wipeMemberships = useMutation({
    mutationFn: () => apiFetch<{ deleted: number }>('/api/v1/admin/memberships', { method: 'DELETE' }),
    onSuccess: () => {
      queryClient.invalidateQueries()
    },
  })

  const resetStudy = useResetStudyCurriculum()
  const deleteAiStudy = useDeleteAiStudyMaterials()
  const resetGenCounters = useResetStudyGenerationCounters()

  // Close on Escape
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  const resetAll = () => {
    if (!window.confirm('다음 데이터가 초기화됩니다:\n• 선택된 사용자 / 카드 토큰\n• 사용자별 대화 매핑\n• 캐싱된 API 응답 및 음성\n\n페이지가 새로고침됩니다.')) return
    try {
      window.localStorage.clear()
      window.sessionStorage.clear()
    } catch {
      /* ignore */
    }
    clearAudioCache()
    queryClient.clear()
    window.location.reload()
  }

  const handleDeleteConversation = async () => {
    if (conversationId === null) {
      window.alert('현재 사용자의 저장된 대화가 없어요.')
      return
    }
    if (!window.confirm('현재 대화와 첨부된 모든 음성을 영구 삭제할까요?\n이 작업은 되돌릴 수 없어요.')) return
    try {
      await deleteConversation(conversationId)
      setConversationForCurrentUser(null)
      clearAudioCache()
      queryClient.invalidateQueries()
      window.alert('대화를 삭제했어요. /conversation 으로 돌아가면 새 대화가 시작됩니다.')
    } catch (e) {
      window.alert(`삭제 실패: ${(e as Error).message}`)
    }
  }

  const handleWipeMemberships = async () => {
    if (!window.confirm('DB의 모든 멤버십을 삭제할까요?\n이 작업은 되돌릴 수 없어요.')) return
    try {
      const result = await wipeMemberships.mutateAsync()
      window.alert(`${result.deleted}개의 멤버십을 삭제했어요.`)
    } catch (e) {
      window.alert(`삭제 실패: ${(e as Error).message}\n관리자 계정으로 전환 후 다시 시도해보세요.`)
    }
  }

  const handleResetStudy = async () => {
    if (!window.confirm('학습 커리큘럼을 리셋할까요?\nAI 생성 토픽이 모두 삭제되고 모든 사용자의 생성 횟수가 초기화돼요.')) return
    try {
      const result = await resetStudy.mutateAsync()
      window.alert(
        `리셋 완료. AI 토픽 ${result.deleted_ai_rows}개 삭제, ` +
          `사용자 카운터 ${result.user_counters_reset}건 초기화, 시드 ${result.seeded}개 재적용.`,
      )
    } catch (e) {
      window.alert(`리셋 실패: ${(e as Error).message}\n관리자 계정으로 전환 후 다시 시도해보세요.`)
    }
  }

  const handleDeleteAiStudy = async () => {
    if (!window.confirm('AI 생성 학습 토픽만 삭제할까요?\n시드 커리큘럼과 사용자 생성 횟수는 그대로 둡니다.')) return
    try {
      const result = await deleteAiStudy.mutateAsync()
      window.alert(`AI 토픽 ${result.deleted}개를 삭제했어요.`)
    } catch (e) {
      window.alert(`삭제 실패: ${(e as Error).message}\n관리자 계정으로 전환 후 다시 시도해보세요.`)
    }
  }

  const handleResetGenCounters = async () => {
    if (!window.confirm('모든 사용자의 AI 생성 횟수와 욕설 카운터를 0으로 초기화할까요?')) return
    try {
      const result = await resetGenCounters.mutateAsync()
      window.alert(`${result.users_reset}명의 카운터를 초기화했어요.`)
    } catch (e) {
      window.alert(`초기화 실패: ${(e as Error).message}\n관리자 계정으로 전환 후 다시 시도해보세요.`)
    }
  }

  return (
    <div className="dev-panel-root">
      <div className={`dev-panel-popover ${open ? 'open' : ''}`} role="dialog" aria-hidden={!open}>
        <div className="dev-panel-header">
          <span>Dev Tools</span>
          <button
            type="button"
            className="dev-panel-close"
            onClick={() => setOpen(false)}
            aria-label="Close"
          >
            ×
          </button>
        </div>

        <div className="dev-panel-section">
          <div className="dev-panel-label">현재 계정 ID</div>
          <div className="dev-panel-value">{currentUserId ?? '—'}</div>
        </div>

        <div className="dev-panel-field">
          <label className="dev-panel-label" htmlFor="dev-user-select">
            계정 전환
          </label>
          <div className="dev-panel-field__row">
            <select
              id="dev-user-select"
              className="dev-panel-select"
              value={currentUserId ?? ''}
              onChange={(e) => setCurrentUserId(Number(e.target.value))}
            >
              {effectiveRoster.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.name} ({u.role})
                </option>
              ))}
            </select>
            {!isAdmin && (
              <button
                type="button"
                className="dev-panel-action small"
                onClick={() => setCurrentUserId(adminId)}
                title="관리자 계정으로 복귀"
              >
                ← Admin
              </button>
            )}
          </div>
        </div>

        <div className="dev-panel-field">
          <label className="dev-panel-label" htmlFor="dev-card-select">
            결제 테스트 카드 (PG mock)
          </label>
          <select
            id="dev-card-select"
            className="dev-panel-select"
            value={selectedCardToken}
            onChange={(e) => setSelectedCardToken(e.target.value)}
            disabled={testCards.isLoading}
          >
            {(testCards.data ?? []).map((c) => (
              <option key={c.token} value={c.token}>
                {c.label} · {c.outcome}
              </option>
            ))}
          </select>
        </div>

        <div className="dev-panel-divider" />

        <button
          type="button"
          className="dev-panel-action danger"
          onClick={handleDeleteConversation}
          disabled={conversationId === null}
          title={conversationId === null ? '현재 대화 없음' : '현재 대화 영구 삭제'}
        >
          현재 대화 삭제 {conversationId !== null && `(#${conversationId})`}
        </button>

        <button
          type="button"
          className="dev-panel-action danger"
          onClick={handleWipeMemberships}
          disabled={wipeMemberships.isPending}
        >
          {wipeMemberships.isPending ? '삭제 중…' : '모든 멤버십 삭제'}
        </button>
        <button
          type="button"
          className="dev-panel-action danger"
          onClick={handleResetStudy}
          disabled={resetStudy.isPending}
        >
          {resetStudy.isPending ? '리셋 중…' : '학습 커리큘럼 리셋'}
        </button>
        <button
          type="button"
          className="dev-panel-action danger"
          onClick={handleDeleteAiStudy}
          disabled={deleteAiStudy.isPending}
        >
          {deleteAiStudy.isPending ? '삭제 중…' : 'AI 생성 토픽만 삭제'}
        </button>
        <button
          type="button"
          className="dev-panel-action danger"
          onClick={handleResetGenCounters}
          disabled={resetGenCounters.isPending}
        >
          {resetGenCounters.isPending ? '초기화 중…' : 'AI 생성 횟수 초기화'}
        </button>
        <button type="button" className="dev-panel-action danger" onClick={resetAll}>
          모든 로컬 데이터 초기화
        </button>

        <div className="dev-panel-info-row">
          <span className="dev-panel-info-icon" tabIndex={0} aria-label="도움말">
            i
            <span className="dev-panel-info-tip" role="tooltip">
              <b>멤버십 삭제</b> — DB의 <code>memberships</code> 테이블을 비웁니다.<br />
              <b>커리큘럼 리셋</b> — AI 토픽 삭제 + 모든 사용자 생성 카운터 0 + 시드 재적용.<br />
              <b>AI 토픽만 삭제</b> — AI 생성 row만 비웁니다 (카운터/시드 보존).<br />
              <b>AI 생성 횟수 초기화</b> — 모든 사용자의 생성 횟수 + 욕설 카운터 0.<br />
              <b>로컬 데이터 초기화</b> — 선택된 사용자·카드 토큰·대화 매핑·캐싱된 API 응답·음성 캐시를 비우고 새로고침.
            </span>
          </span>
        </div>
      </div>

      <button
        type="button"
        className={`dev-panel-fab ${open ? 'open' : ''}`}
        onClick={() => setOpen((v) => !v)}
        aria-label="Open developer panel"
        title="Dev tools"
      >
        <WrenchIcon />
      </button>
    </div>
  )
}

function WrenchIcon() {
  return (
    <svg
      width="22"
      height="22"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M14.7 6.3a4 4 0 0 0-5.4 5.4l-6 6a1.4 1.4 0 0 0 2 2l6-6a4 4 0 0 0 5.4-5.4l-2.5 2.5-2-2 2.5-2.5z" />
    </svg>
  )
}
