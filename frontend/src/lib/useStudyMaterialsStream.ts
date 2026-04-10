// Subscribes to /api/v1/study_materials/stream (SSE) and invalidates
// the React Query cache for the study materials list whenever the
// server pushes a `changed` event. Two triggers fire that event:
//
//   1. Any user runs `StudyMaterials::Generate` (their per-user cap
//      gets bumped, the curriculum table gains a row, and every other
//      open /study tab repaints to include the new row in the AI
//      bucket).
//
//   2. The admin clicks "커리큘럼 리셋" in the dev panel — the
//      `StudyMaterials::Reset` service wipes AI rows, re-runs the
//      seed, and publishes once. Every learner currently on /study
//      sees the fresh rotation immediately.
//
// Auth: forwards the active user id via `?user_id=…` because
// EventSource cannot set custom request headers.

import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { queryKeys } from './queries'
import { useUserStore } from './userStore'

const BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '')

export function useStudyMaterialsStream(): void {
  const userId = useUserStore((s) => s.currentUserId)
  const qc = useQueryClient()

  useEffect(() => {
    if (userId === null) return

    const url = new URL('/api/v1/study_materials/stream', BASE_URL)
    url.searchParams.set('user_id', String(userId))
    const es = new EventSource(url.toString())

    console.info('[study/stream] connecting →', url.toString())
    es.addEventListener('open', () => console.info('[study/stream] open'))
    es.addEventListener('error', (e) => console.warn('[study/stream] error', e))
    es.addEventListener('ready', () => console.info('[study/stream] ready'))
    es.addEventListener('heartbeat', () => console.debug('[study/stream] heartbeat'))

    const onChanged = () => {
      console.info('[study/stream] changed → invalidating studyMaterials')
      qc.invalidateQueries({ queryKey: queryKeys.studyMaterials })
      // Generation events also affect the per-user generation counter
      // surfaced in /me, so invalidate that too.
      qc.invalidateQueries({ queryKey: ['me'] })
    }
    es.addEventListener('changed', onChanged)

    return () => {
      console.info('[study/stream] closing')
      es.removeEventListener('changed', onChanged)
      es.close()
    }
  }, [userId, qc])
}
