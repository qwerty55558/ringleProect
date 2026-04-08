import '@testing-library/jest-dom/vitest'
import { afterEach } from 'vitest'
import { cleanup } from '@testing-library/react'

// jsdom under vitest@4 occasionally hands back a Storage shim that doesn't
// implement setItem; provide a minimal in-memory polyfill so zustand's
// persist middleware doesn't blow up in tests.
class MemoryStorage {
  private data = new Map<string, string>()
  get length() { return this.data.size }
  clear() { this.data.clear() }
  getItem(k: string) { return this.data.get(k) ?? null }
  setItem(k: string, v: string) { this.data.set(k, String(v)) }
  removeItem(k: string) { this.data.delete(k) }
  key(i: number) { return Array.from(this.data.keys())[i] ?? null }
}
Object.defineProperty(globalThis, 'localStorage', { value: new MemoryStorage(), writable: true })

afterEach(() => cleanup())
