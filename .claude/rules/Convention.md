## Frontend (TypeScript + React)

### Component Reuse

- **Reuse before you build.** Before creating a new component, search the codebase for an existing one that already covers the use case. Extend or compose it instead of duplicating.
- **Extract on the second occurrence.** When the same markup, styling, or behavior appears in two or more places, lift it into a shared component or hook.
- **Prefer composition over duplication.** Build screens by composing small, focused primitives rather than copy-pasting JSX blocks.
- **Co-locate by scope.** Page-specific components stay next to the page; cross-page primitives live in a shared `components/` (or equivalent) directory.
- **Name by intent, not by appearance.** Component names should describe what they represent (`SessionCard`), not how they look (`BlueBox`).
- **No dead variants.** If a prop or variant is no longer used after a refactor, remove it instead of leaving it for "future use".

### Styling

- **Use a shared `global.css`.** All shared styles — design tokens (colors, spacing, typography, radii, shadows), resets, base element styles, and reusable utility/component classes — live in a single `global.css` (imported once at the app entry). Do not redefine the same values in multiple places.
- **Style via `className` only.** Apply styles by attaching class names defined in `global.css` (or a co-located `.css` file that follows the same conventions). Do **not** use inline `style={{ ... }}` props except for truly dynamic values that cannot be expressed as a class (e.g., a computed transform from runtime data).
- **No CSS-in-JS / no styled-components.** Keep styling in plain CSS files so the rules are greppable and reusable across components.
- **Tokens over magic values.** Reference CSS custom properties (e.g., `var(--color-primary)`, `var(--space-4)`) defined in `global.css` instead of hard-coding hex codes or pixel values inside component styles.
- **Class names describe intent.** Prefer semantic, component-scoped class names (`session-card`, `session-card__title`) over presentational ones (`blue-box`, `mt-12`). If you introduce a utility class, put it in `global.css` so it can be reused.
- **One source of truth per token.** When a color or spacing value needs to change, it should change in exactly one place in `global.css`.
