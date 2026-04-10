// Render-nothing component whose only job is to keep the /me/stream
// SSE subscription alive for the lifetime of the app. Mounted once at
// the App root, NOT inside a route — that way every page (home, admin,
// study, analysis, conversation) reacts to membership state changes
// the moment the server pushes them, with a single shared connection.
//
// The subscription itself lives in `useMeStream`. This wrapper exists
// purely so the hook has a stable mount point that survives route
// transitions; mounting it inside a per-route guard would tear down
// and re-open the EventSource on every navigation.

import { useMeStream } from '../lib/useMeStream'

export function MeStreamSubscriber() {
  useMeStream()
  return null
}
