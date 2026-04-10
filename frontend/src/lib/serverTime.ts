let offsetMs = 0

const TZ_OFFSET_HOURS = import.meta.env.VITE_TZ_OFFSET !== undefined
  ? Number(import.meta.env.VITE_TZ_OFFSET)
  : 0

export function setServerTimeOffset(serverIso: string): void {
  const serverMs = new Date(serverIso).getTime()
  const clientMs = Date.now()
  offsetMs = serverMs - clientMs
}

export function getServerNow(): Date {
  return new Date(Date.now() + offsetMs)
}

export function formatServerDate(iso: string): string {
  const utcMs = new Date(iso).getTime()
  const localMs = utcMs + TZ_OFFSET_HOURS * 3600000
  const d = new Date(localMs)
  const y = d.getUTCFullYear()
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0')
  const day = String(d.getUTCDate()).padStart(2, '0')
  return `${y}-${mo}-${day}`
}

export function formatServerTime(iso: string): string {
  const utcMs = new Date(iso).getTime()
  const localMs = utcMs + TZ_OFFSET_HOURS * 3600000
  const d = new Date(localMs)
  const y = d.getUTCFullYear()
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0')
  const day = String(d.getUTCDate()).padStart(2, '0')
  const h = String(d.getUTCHours()).padStart(2, '0')
  const mi = String(d.getUTCMinutes()).padStart(2, '0')
  const s = String(d.getUTCSeconds()).padStart(2, '0')
  return `${y}-${mo}-${day} ${h}:${mi}:${s}`
}
