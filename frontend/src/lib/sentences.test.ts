import { describe, expect, it } from 'vitest'
import { SentenceSplitter } from './sentences'

describe('SentenceSplitter', () => {
  it('returns complete sentences as they arrive', () => {
    const s = new SentenceSplitter()
    expect(s.feed('Hello there. ')).toEqual(['Hello there.'])
    expect(s.feed('How are you')).toEqual([])
    expect(s.feed('? I am ')).toEqual(['How are you?'])
    expect(s.flush()).toEqual('I am')
  })

  it('handles multiple sentences in one delta', () => {
    const s = new SentenceSplitter()
    expect(s.feed('First one. Second one! Third one? ')).toEqual([
      'First one.',
      'Second one!',
      'Third one?',
    ])
  })

  it('skips fragments shorter than MIN_LEN at the start', () => {
    const s = new SentenceSplitter()
    // "Oh." is too short on its own — we hold it
    expect(s.feed('Oh. ')).toEqual([])
    expect(s.feed("That's nice today. ")).toEqual(["Oh. That's nice today."])
  })
})
