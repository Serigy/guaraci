# Implementation Stories

| Order | Story | Epic | Status | Prerequisites |
|---:|---|---|---|---|
| 1 | `epic-1-story-1.md` — Parse endpoint options and render deterministic templates | Epic 1 — CLI scaffolding | Ready | none |
| 2 | `epic-1-story-2.md` — Wire the endpoint generator and safe file creation | Epic 1 — CLI scaffolding | Draft | Story 1 |
| 3 | `epic-2-story-1.md` — Register and reset route introspection metadata | Epic 2 — Introspection/OpenAPI | Draft | Story 2 |
| 4 | `epic-2-story-2.md` — Build and serve the live simplified OpenAPI document | Epic 2 — Introspection/OpenAPI | Draft | Story 3 |
| 5 | `epic-2-story-3.md` — Activate the explorer with production fail-closed behavior | Epic 2 — Introspection/OpenAPI | Draft | Story 4 |
| 6 | `epic-3-story-1.md` — Serve the static same-origin explorer shell and assets | Epic 3 — Explorer web interface | Draft | Story 5 |
| 7 | `epic-3-story-2.md` — Implement explorer request forms, responses, and CSRF handling | Epic 3 — Explorer web interface | Draft | Story 6 |
| 8 | `epic-4-story-1.md` — Document, validate, and prepare the release | Epic 4 — Documentation/release | Draft | Stories 2, 5, and 7 |

## Dependency chain

`E1-S1 → E1-S2 → E2-S1 → E2-S2 → E2-S3 → E3-S1 → E3-S2 → E4-S1`

Epic 4 is gated by the completed CLI, activation, and UI chains. The Developer should start with **Epic 1 Story 1**.
