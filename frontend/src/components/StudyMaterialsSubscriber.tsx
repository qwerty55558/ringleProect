// Render-nothing wrapper for the study curriculum SSE channel.
// Mounted ONCE at App root so every page (not just /study) reacts
// when the curriculum changes — for example, the dev panel can issue
// a reset from any page and the next time the user visits /study
// they're already on the fresh rotation.

import { useStudyMaterialsStream } from '../lib/useStudyMaterialsStream'

export function StudyMaterialsSubscriber() {
  useStudyMaterialsStream()
  return null
}
