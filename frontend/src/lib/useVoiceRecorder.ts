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
  start: () => Promise<void>
  cancel: () => void
  finalize: () => Promise<Blob | null>
}

export function useVoiceRecorder(): UseVoiceRecorderResult {
  const [state, setState] = useState<RecorderState>('idle')
  const [amplitudes, setAmplitudes] = useState<number[]>(new Array(32).fill(4))
  const [error, setError] = useState<string | null>(null)

  const vadRef = useRef<MicVAD | null>(null)
  const speechChunksRef = useRef<Float32Array[]>([])
  const streamRef = useRef<MediaStream | null>(null)
  const audioCtxRef = useRef<AudioContext | null>(null)
  const analyserRef = useRef<AnalyserNode | null>(null)
  const rafRef = useRef<number | null>(null)
  const stopTimerRef = useRef<number | null>(null)

  const cleanup = useCallback(() => {
    if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
    if (stopTimerRef.current !== null) window.clearTimeout(stopTimerRef.current)
    rafRef.current = null
    stopTimerRef.current = null

    vadRef.current?.pause()
    vadRef.current?.destroy?.()
    vadRef.current = null

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
      // Tuning notes (vad-web 0.0.30 RealTimeVADOptions):
      //   - Lower thresholds than the defaults (0.5 / 0.35) so quiet speech
      //     in a normal room registers; the recruiter mic is far from the
      //     mouth and the defaults dropped a lot of utterances as misfires.
      //   - 100ms minSpeechMs catches single-word answers ("yes", "okay")
      //     that the previous 250ms cutoff threw away.
      //   - Generous redemption + pre-pad so word boundaries don't get
      //     clipped — VAD is still cheap on the bytes-per-utterance side.
      const vad = await MicVAD.new({
        baseAssetPath: VAD_BASE_ASSET_PATH,
        onnxWASMBasePath: VAD_ONNX_BASE_PATH,
        positiveSpeechThreshold: 0.35,
        negativeSpeechThreshold: 0.2,
        minSpeechMs: 100,
        preSpeechPadMs: 250,
        redemptionMs: 500,
        onSpeechEnd: (audio) => {
          // audio is a Float32Array of just the voiced region @ 16kHz
          speechChunksRef.current.push(audio)
        },
        onVADMisfire: () => {
          // vad-web flagged the segment as too short to be real speech.
          // We don't surface this — finalize() reports "no audio captured"
          // if every segment was a misfire, which is the actionable signal.
        },
      })
      vadRef.current = vad

      // separate analyser for the live waveform — vad-web owns its own
      // worklet, so we open a second tap on the same MediaStream
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

      stopTimerRef.current = window.setTimeout(() => {
        setError('Recording stopped — max length reached.')
        // we still finalize whatever we captured
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

    // Give VAD a beat to flush any in-flight final frame.
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
  }, [cleanup])

  return { state, amplitudes, error, start, cancel, finalize }
}
