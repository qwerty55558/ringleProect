import { useEffect } from 'react'
import { useUserStore } from './userStore'

const BASE_URL = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '')

export function useAnalysisStream(onChanged: () => void): void {
  const userId = useUserStore((s) => s.currentUserId)

  useEffect(() => {
    if (userId === null) return

    const url = `${BASE_URL}/api/v1/analysis/stream?user_id=${userId}`
    const es = new EventSource(url)

    es.addEventListener('changed', () => {
      onChanged()
    })

    es.onerror = () => {
      // reconnect is automatic with EventSource
    }

    return () => es.close()
  }, [userId, onChanged])
}
