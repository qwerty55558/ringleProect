// Shared full-page loading state. Every page that gates render on an
// async fetch should use this instead of hand-rolling its own
// `<div className="empty-state"><div className="spinner" /> …</div>`
// markup, so the spinner copy and layout stay consistent.
//
// Variants:
//   - default `block` variant centers in the page main column
//   - `inline` variant fits inside a card or section without forcing
//     extra vertical space (used by RequireAccess and DevPanel)

type Props = {
  message?: string
  variant?: 'block' | 'inline'
}

export function LoadingScreen({ message = '불러오는 중…', variant = 'block' }: Props) {
  const className = variant === 'inline' ? 'loading-screen loading-screen--inline' : 'loading-screen'
  return (
    <div className={className} role="status" aria-live="polite">
      <div className="spinner" />
      <span>{message}</span>
    </div>
  )
}
