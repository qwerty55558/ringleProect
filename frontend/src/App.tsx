import { Route, Routes } from 'react-router-dom'
import { TopBar } from './components/TopBar'
import { DevPanel } from './components/DevPanel'
import { RequireAccess } from './components/RequireAccess'
import { MeStreamSubscriber } from './components/MeStreamSubscriber'
import { StudyMaterialsSubscriber } from './components/StudyMaterialsSubscriber'
import { HomePage } from './pages/HomePage'
import { HistoryPage } from './pages/HistoryPage'
import { AdminPage } from './pages/AdminPage'
import { ConversationPage } from './pages/ConversationPage'
import { StudyPage } from './pages/StudyPage'
import { AnalysisPage } from './pages/AnalysisPage'

// Page-level access guards. The backend is the real enforcer (every
// controller has a require_*! before_action that re-checks DB state on
// each call) — these wrappers are the friendly UX layer so a learner
// without `talk` doesn't see the conversation page flash before getting
// 403'd.
//
// Real-time membership state lives one level higher: <MeStreamSubscriber/>
// is mounted once for the whole app session and pushes /me snapshots
// into the React Query cache from /api/v1/me/stream. Every page that
// reads via useMe() therefore reacts to grants / revokes / expiry the
// instant they happen, no per-page wiring required.
export default function App() {
  return (
    <div className="app">
      <MeStreamSubscriber />
      <StudyMaterialsSubscriber />
      <TopBar />
      <main className="app-main">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/history" element={<HistoryPage />} />
          <Route
            path="/study"
            element={
              <RequireAccess feature="study">
                <StudyPage />
              </RequireAccess>
            }
          />
          <Route
            path="/conversation"
            element={
              <RequireAccess feature="talk">
                <ConversationPage />
              </RequireAccess>
            }
          />
          <Route
            path="/analysis"
            element={
              <RequireAccess feature="analysis">
                <AnalysisPage />
              </RequireAccess>
            }
          />
          <Route
            path="/admin"
            element={
              <RequireAccess role="admin">
                <AdminPage />
              </RequireAccess>
            }
          />
          <Route path="*" element={<HomePage />} />
        </Routes>
      </main>
      <DevPanel />
    </div>
  )
}
