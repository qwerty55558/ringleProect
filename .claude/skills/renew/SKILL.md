---
name: renew
description: Explicit-invocation only. Run when the user types `/renew` (or explicitly asks to renew the docs). Re-syncs README.md and docs/coding_agent_interaction_history.md against the current code state and the assignment PDF. Do NOT auto-trigger from keyword matches in normal conversation.
---

# renew

Syncs `README.md` and `docs/coding_agent_interaction_history.md` against the actual codebase.

## Two docs, two jobs

1. **README.md** — project structure, tech stack, design docs for reviewers. Must match the code.
2. **interaction_history.md** — assignment requirement #3: AI tool usage log. Must **accumulate** new work done with AI each session (features built, decisions made, user feedback applied, bugs fixed). Not just code-correctness — capture the development narrative.

## On invocation

1. **Audit**: scan backend (models, controllers, services, routes, migrations, schema) + frontend (pages, components, lib, tests) + infra (Docker, CI). Diff against current docs.
2. **README**: fix stale facts (counts, file lists, diagrams, feature descriptions). Minimum edits — only what's wrong.
3. **Interaction history**: append new sections for work done since last update. Don't touch existing sections except stale numbers (test counts etc). Add `[SCREENSHOT: ...]` markers.
4. **Report**: ASCII-box summary of changes. Surface any doc-vs-code contradictions that need a code change to fix.

## Rules

- PDF and code are the only authorities. Docs follow them.
- Document-only — never edit app code, migrations, or the PDF.
- README: minimum-viable edits. Interaction history: additive (append new sections).
- No fabricated file paths, function names, or counts — verify by reading.
- Respect `CLAUDE.md` directory scoping (backend/ vs frontend/).
- On contradiction between PDF and code, surface both sides — don't pick.
- ASCII box tables only (no markdown tables). Korean prose, English identifiers.

## Skip when

No significant code changes since last run (typos, comment tweaks only).
