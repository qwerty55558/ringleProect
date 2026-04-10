export function toSpeakable(text: string): string {
  return text.replace(/_+/g, 'blank')
}
