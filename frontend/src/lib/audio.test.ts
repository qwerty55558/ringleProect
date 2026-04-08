import { describe, expect, it } from 'vitest'
import { concatFloat32, encodeWav } from './audio'

describe('concatFloat32', () => {
  it('joins multiple chunks in order', () => {
    const out = concatFloat32([new Float32Array([1, 2]), new Float32Array([3, 4, 5])])
    expect(Array.from(out)).toEqual([1, 2, 3, 4, 5])
  })
  it('returns an empty array for no chunks', () => {
    expect(concatFloat32([]).length).toBe(0)
  })
})

describe('encodeWav', () => {
  it('produces a RIFF/WAVE header followed by PCM data', async () => {
    const blob = encodeWav(new Float32Array([0, 0.5, -0.5, 1, -1]), 16_000)
    const buf = new Uint8Array(await blob.arrayBuffer())
    const ascii = String.fromCharCode(...buf.slice(0, 4))
    const wave = String.fromCharCode(...buf.slice(8, 12))
    expect(ascii).toBe('RIFF')
    expect(wave).toBe('WAVE')
    // 44-byte header + 5 samples * 2 bytes
    expect(buf.byteLength).toBe(44 + 10)
  })
})
