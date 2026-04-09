// "지난 멤버십" — read-only audit list of every membership the current
// user used to hold and no longer does. Lives at /history and is linked
// from the bottom of the home page's "나의 멤버십" card.
//
// We deliberately reuse the same /me payload (and therefore the same
// React Query cache) instead of adding a backend endpoint: the data is
// already there, history rows are tiny, and this keeps the SSE
// invalidation pipeline working transparently — when a membership
// expires mid-session the home page AND this page both update from
// the next /me/stream snapshot.

import { Link } from 'react-router-dom'
import { useMe } from '../lib/queries'
import { useUserStore } from '../lib/userStore'
import { LoadingScreen } from '../components/LoadingScreen'
import { MembershipRow } from '../components/MembershipRow'

export function HistoryPage() {
  const currentUserId = useUserStore((s) => s.currentUserId)
  const me = useMe()

  if (currentUserId === null) {
    return <div className="empty-state">상단에서 계정을 선택해주세요.</div>
  }
  if (me.isLoading || !me.data) {
    return <LoadingScreen message="멤버십 히스토리 불러오는 중…" />
  }

  // Anything that isn't currently active counts as history. We sort
  // newest first by `started_at` so the most recent expiry / revoke
  // shows up at the top — that's the row a learner is most likely
  // looking for ("did my plan really expire just now?").
  const historyItems = me.data.memberships
    .filter((m) => m.state !== 'active')
    .sort((a, b) => Date.parse(b.started_at) - Date.parse(a.started_at))

  return (
    <div className="page-enter">
      <section className="hero">
        <div>
          <h1>지난 멤버십</h1>
          <p>만료되었거나 회수된 멤버십 기록이에요.</p>
        </div>
        <Link to="/" className="btn ghost">
          ← 홈으로
        </Link>
      </section>

      <section className="card">
        <div className="section-header">
          <h2>히스토리</h2>
          <span className="muted">{historyItems.length}건</span>
        </div>
        {historyItems.length === 0 ? (
          <p className="empty-state">아직 만료된 멤버십이 없어요.</p>
        ) : (
          <div className="membership-list">
            {historyItems.map((m, i) => (
              <div key={m.id} className="stagger-item" style={{ '--i': i } as React.CSSProperties}>
                <MembershipRow membership={m} />
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
