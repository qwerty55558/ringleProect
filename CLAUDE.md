## Project Principles

- **AI-assisted development is mandatory.** Use AI coding tools (e.g., GitHub Copilot, Cursor, OpenAI Codex, Claude Code) throughout implementation. Unfamiliarity with a given language or framework is not a blocker — leverage AI tools to meet the requirements.
- **Backend** is implemented with **Ruby on Rails**.
- **Frontend** is implemented with **TypeScript + React**.
- **Persistent storage is required.** State must survive service restarts; use a database (or equivalent persistent storage) rather than in-memory state.
- **Design for flexibility and extensibility.** Avoid hard-coded, single-purpose structures; favor designs that can evolve as requirements grow.
- **Write review-grade code, not just code that runs.** Every change should be at a quality level you would be comfortable putting up for peer review.
- **High-quality tests are mandatory.** Meaningful test coverage is a hard requirement, not an optional add-on.

## Conventions

Follow the conventions defined in `.claude/rules/Convention.md` for all work in this repository.

## Comments

Keep comments short — one line max, only when the *why* isn't obvious from the code. No banner blocks, no file headers, no narrating what a function does.

## Search scoping (token discipline)

- **Frontend work must scope every Glob/Grep/Read to `frontend/`.** Never scan the project root or `backend/` for frontend questions.
- **Backend work must scope every Glob/Grep/Read to `backend/`.** Never scan `frontend/` for backend questions.
- **Do not "scan" the codebase opportunistically.** Without an explicit instruction from the user (e.g. "전체 검색해", "양쪽 다 봐"), assume the relevant directory is the only one in scope and stay there.
- Cross-directory exploration is allowed only when the user asks for it or when the task is explicitly full-stack (e.g. matching an API contract between Rails and the React client). In that case, narrow each individual search to the smallest path that still answers the question.
- This rule exists to keep token usage down — every unnecessary directory walk wastes context. When in doubt, ask before broadening the scope.
