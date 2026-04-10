export function toSpeakable(text: string): string {
  return text.replace(/_+/g, 'something').trim()
}
