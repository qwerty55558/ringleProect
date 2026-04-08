// Sequential audio playback queue.
//
// The conversation flow streams the LLM reply token-by-token. Rather than
// waiting for the full reply before kicking off TTS, we split the stream on
// sentence boundaries and fire a TTS request for each finished sentence in
// parallel. The audio blobs come back in (roughly) the order they were
// requested but we don't trust that — this queue plays them strictly in
// order, even if a later sentence's TTS finishes first.
//
//   queue.enqueue(promiseOfBlob)   // promise resolving to an MP3 blob
//   queue.stop()                   // cancel everything
//
// Each `enqueue` call returns immediately; the queue plays clips back-to-back
// in arrival order. The queue is reusable across turns.

type Item = {
  promise: Promise<Blob | null>
}

export class AudioQueue {
  private items: Item[] = []
  private playing = false
  private current: HTMLAudioElement | null = null
  private cancelled = false

  enqueue(promise: Promise<Blob | null>): void {
    if (this.cancelled) return
    this.items.push({ promise })
    void this.drain()
  }

  stop(): void {
    this.cancelled = true
    this.items = []
    if (this.current) {
      this.current.pause()
      this.current.src = ''
      this.current = null
    }
    this.playing = false
  }

  reset(): void {
    this.stop()
    this.cancelled = false
  }

  private async drain(): Promise<void> {
    if (this.playing) return
    this.playing = true

    while (this.items.length > 0 && !this.cancelled) {
      const item = this.items.shift()!
      let blob: Blob | null
      try {
        blob = await item.promise
      } catch {
        continue
      }
      if (!blob || this.cancelled) continue

      await this.playOne(blob)
    }

    this.playing = false
  }

  private playOne(blob: Blob): Promise<void> {
    return new Promise((resolve) => {
      const url = URL.createObjectURL(blob)
      const audio = new Audio(url)
      this.current = audio
      const cleanup = () => {
        URL.revokeObjectURL(url)
        if (this.current === audio) this.current = null
        resolve()
      }
      audio.onended = cleanup
      audio.onerror = cleanup
      audio.play().catch(cleanup)
    })
  }
}
