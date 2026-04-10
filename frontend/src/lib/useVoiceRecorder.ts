// Hook that manages a single press-to-talk session:
//
//   - opens the user microphone via getUserMedia
//   - runs Silero VAD via @ricky0123/vad-web on every frame
//   - keeps only the voiced audio chunks (this is the "VAD trimming" the spec
//     calls out — silent regions are never sent to the STT endpoint)
//   - publishes a live amplitude buffer so the page can render a waveform
//   - hard-caps each utterance at MAX_RECORDING_MS to prevent runaway sessions
//
// The hook intentionally exposes a small surface (start/stop/state/amplitudes)
// so the page component stays mostly markup.

import { useCallback, useEffect, useRef, useState } from 'react'
import { MicVAD } from '@ricky0123/vad-web'
import { concatFloat32, encodeWav } from './audio'

const MAX_RECORDING_MS = 30_000        // hard cap so a stuck mic can't bleed quota
const IDLE_TIMEOUT_MS  = 10_000        // auto-cancel if no speech detected for 10s
const VAD_SAMPLE_RATE  = 16_000        // vad-web feeds back 16kHz mono float32
// Served locally from public/vad/ — see vite.config.ts → vadAssetsPlugin.
// We used to load from a CDN; jsdelivr occasionally 404s the .onnx file
// which silently breaks the recorder.
const VAD_BASE_ASSET_PATH = '/vad/'
const VAD_ONNX_BASE_PATH  = '/vad/'

export type RecorderState = 'idle' | 'starting' | 'recording' | 'stopping' | 'error'

type UseVoiceRecorderResult = {
  state: RecorderState
  amplitudes: number[]
  error: string | null
  idlePrompt: boolean
  start: () => Promise<void>
  cancel: () => void
  finalize: () => Promise<Blob | null>
  dismissIdlePrompt: () => void
  simulate: (blob: Blob) => Promise<Blob>
}

export function useVoiceRecorder(): UseVoiceRecorderResult {
  const [state, setState] = useState<RecorderState>('idle')
  const [amplitudes, setAmplitudes] = useState<number[]>(new Array(32).fill(4))
  const [error, setError] = useState<string | null>(null)
  const [idlePrompt, setIdlePrompt] = useState(false)

  const vadRef = useRef<MicVAD | null>(null)
  const speechChunksRef = useRef<Float32Array[]>([])
  const streamRef = useRef<MediaStream | null>(null)
  const audioCtxRef = useRef<AudioContext | null>(null)
  const analyserRef = useRef<AnalyserNode | null>(null)
  const rafRef = useRef<number | null>(null)
  const stopTimerRef = useRef<number | null>(null)
  const idleTimerRef = useRef<number | null>(null)

  const cleanup = useCallback(() => {
    if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
    if (stopTimerRef.current !== null) window.clearTimeout(stopTimerRef.current)
    if (idleTimerRef.current !== null) window.clearTimeout(idleTimerRef.current)
    rafRef.current = null
    stopTimerRef.current = null
    idleTimerRef.current = null

    vadRef.current?.pause()
    // VAD를 destroy하지 않음 — onnxruntime 재초기화 시 실패하므로 재사용

    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null

    audioCtxRef.current?.close().catch(() => undefined)
    audioCtxRef.current = null
    analyserRef.current = null
  }, [])

  useEffect(() => () => cleanup(), [cleanup])

  const start = useCallback(async () => {
    if (state === 'recording' || state === 'starting') return
    setError(null)
    setState('starting')
    speechChunksRef.current = []

    try {
      if (!vadRef.current) {
        const vad = await MicVAD.new({
          baseAssetPath: VAD_BASE_ASSET_PATH,
          onnxWASMBasePath: VAD_ONNX_BASE_PATH,
          positiveSpeechThreshold: 0.35,
          negativeSpeechThreshold: 0.2,
          minSpeechMs: 100,
          preSpeechPadMs: 250,
          redemptionMs: 500,
          onSpeechEnd: (audio) => {
            speechChunksRef.current.push(audio)
            if (idleTimerRef.current !== null) window.clearTimeout(idleTimerRef.current)
            idleTimerRef.current = window.setTimeout(() => {
              setIdlePrompt(true)
            }, IDLE_TIMEOUT_MS)
          },
          onVADMisfire: () => {},
        })
        vadRef.current = vad
      }

      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      streamRef.current = stream
      const ctx = new AudioContext()
      audioCtxRef.current = ctx
      const source = ctx.createMediaStreamSource(stream)
      const analyser = ctx.createAnalyser()
      analyser.fftSize = 64
      source.connect(analyser)
      analyserRef.current = analyser

      const buf = new Uint8Array(analyser.frequencyBinCount)
      const tick = () => {
        analyser.getByteFrequencyData(buf)
        const next: number[] = []
        for (let i = 0; i < buf.length; i++) next.push(Math.max(4, (buf[i] / 255) * 60))
        setAmplitudes(next)
        rafRef.current = requestAnimationFrame(tick)
      }
      tick()

      vad.start()
      setState('recording')

      idleTimerRef.current = window.setTimeout(() => {
        cleanup()
        speechChunksRef.current = []
        setState('idle')
        setError('음성이 감지되지 않아 녹음이 종료되었어요.')
      }, IDLE_TIMEOUT_MS)

      stopTimerRef.current = window.setTimeout(() => {
        setError('Recording stopped — max length reached.')
      }, MAX_RECORDING_MS)
    } catch (e: unknown) {
      cleanup()
      setError(e instanceof Error ? e.message : 'Failed to start recording')
      setState('error')
    }
  }, [state, cleanup])

  const finalize = useCallback(async (): Promise<Blob | null> => {
    if (state !== 'recording' && state !== 'starting') return null
    setState('stopping')
    setIdlePrompt(false)

    await new Promise((r) => setTimeout(r, 120))
    vadRef.current?.pause()

    const merged = concatFloat32(speechChunksRef.current)
    cleanup()
    setState('idle')
    if (merged.length === 0) return null
    return encodeWav(merged, VAD_SAMPLE_RATE)
  }, [state, cleanup])

  const cancel = useCallback(() => {
    cleanup()
    speechChunksRef.current = []
    setState('idle')
    setError(null)
    setIdlePrompt(false)
  }, [cleanup])

  const dismissIdlePrompt = useCallback(() => {
    setIdlePrompt(false)
  }, [])

  // Plays a pre-recorded WAV (typically a server-side fixture) through
  // an AudioContext so the listener can hear it AND so an AnalyserNode
  // tap drives the same waveform UI that real mic input does. Resolves
  // with the input blob unchanged so the caller can pipe it straight to
  // /api/v1/ai/transcriptions, where the StttArtifact cache will hit.
  const simulate = useCallback(
    async (blob: Blob): Promise<Blob> => {
      if (state === 'recording' || state === 'starting') {
        cleanup()
      }
      setError(null)
      setState('starting')

      try {
        const ctx = new AudioContext()
        audioCtxRef.current = ctx
        const arrayBuffer = await blob.arrayBuffer()
        // decodeAudioData mutates the buffer on some browsers; pass a copy
        const audioBuffer = await ctx.decodeAudioData(arrayBuffer.slice(0))

        const source = ctx.createBufferSource()
        source.buffer = audioBuffer

        const analyser = ctx.createAnalyser()
        analyser.fftSize = 64
        analyserRef.current = analyser

        source.connect(analyser)
        // Also route to speakers so the recruiter can hear the "speech"
        analyser.connect(ctx.destination)

        const buf = new Uint8Array(analyser.frequencyBinCount)
        const tick = () => {
          analyser.getByteFrequencyData(buf)
          const next: number[] = []
          for (let i = 0; i < buf.length; i++) next.push(Math.max(4, (buf[i] / 255) * 60))
          setAmplitudes(next)
          rafRef.current = requestAnimationFrame(tick)
        }

        return await new Promise<Blob>((resolve) => {
          source.onended = () => {
            cleanup()
            setState('idle')
            resolve(blob)
          }
          source.start()
          setState('recording')
          tick()
        })
      } catch (e: unknown) {
        cleanup()
        setError(e instanceof Error ? e.message : 'Failed to play fixture')
        setState('error')
        throw e
      }
    },
    [state, cleanup],
  )

  return { state, amplitudes, error, idlePrompt, start, cancel, finalize, dismissIdlePrompt, simulate }
}
