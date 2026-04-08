import { Route, Routes } from 'react-router-dom'
import { TopBar } from './components/TopBar'
import { DevPanel } from './components/DevPanel'
import { HomePage } from './pages/HomePage'
import { AdminPage } from './pages/AdminPage'
import { ConversationPage } from './pages/ConversationPage'
import './App.css'

export default function App() {
  return (
    <div className="app">
      <TopBar />
      <main className="app-main">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/admin" element={<AdminPage />} />
          <Route path="/conversation" element={<ConversationPage />} />
          <Route path="*" element={<HomePage />} />
        </Routes>
      </main>
      <DevPanel />
    </div>
  )
}
