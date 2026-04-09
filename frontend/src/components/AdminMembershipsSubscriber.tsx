// Render-nothing wrapper for the admin-only SSE channel that
// invalidates the admin/users React Query whenever ANY membership
// row changes anywhere in the database. Mounted from inside
// <AdminPage/> so the connection only exists while the dashboard is
// on screen — when the admin navigates away, the EventSource closes
// and the server-side subscriber is unregistered.

import { useAdminMembershipsStream } from '../lib/useAdminMembershipsStream'

export function AdminMembershipsSubscriber() {
  useAdminMembershipsStream()
  return null
}
