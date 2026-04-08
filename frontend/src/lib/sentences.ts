// Tiny stateful sentence splitter for streaming LLM output.
//
// We get text deltas one at a time. Each call to `feed(delta)` returns any
// complete sentences that just became available, and `flush()` returns
// whatever's left in the buffer at the end of the stream.
//
// "Complete" = ends with `.`, `!`, or `?` followed by whitespace or EOL.
// We require at least MIN_LEN characters per emitted chunk so we don't ship
// stand-alone interjections like "Oh." (clipped TTS sounds bad). Short
// fragments are merged with the next sentence — concretely, we skip past
// short terminators with a cursor and keep scanning until we find a long
// enough span.

export class SentenceSplitter {
  private buffer = ''
  private static readonly END_RE = /([.!?])(\s+|$)/
  private static readonly MIN_LEN = 6

  feed(delta: string): string[] {
    this.buffer += delta
    const out: string[] = []
    let cursor = 0

    while (cursor <= this.buffer.length) {
      const m = SentenceSplitter.END_RE.exec(this.buffer.slice(cursor))
      if (!m) break

      const absoluteEnd = cursor + m.index + 1
      const candidate = this.buffer.slice(0, absoluteEnd).trim()
      const consumeUpTo = absoluteEnd + m[2].length

      if (candidate.length < SentenceSplitter.MIN_LEN) {
        // Too short on its own — advance cursor past this terminator
        // (without emitting) so we can try to combine with later text.
        cursor = consumeUpTo
        continue
      }

      out.push(candidate)
      this.buffer = this.buffer.slice(consumeUpTo)
      cursor = 0
    }
    return out
  }

  flush(): string | null {
    const rest = this.buffer.trim()
    this.buffer = ''
    return rest.length > 0 ? rest : null
  }

  reset(): void {
    this.buffer = ''
  }
}
