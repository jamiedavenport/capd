# TODOS

Deferred scope from /office-hours + /plan-ceo-review (2026-08-02). Full context:
`~/.gstack/projects/cap/ceo-plans/2026-08-02-cap-v0.1.md`.

## P2 — launch-adjacent

- [ ] **E3: `cap import safari|chrome|pinboard <file>`** (S-M human / S with CC)
  Why: day-one non-empty search; the ex-Pinboard switching lever. User chose to keep
  this deferred even for the dogfood gate (gate runs cold-start, metric is directional).
  Trigger: at launch, or first user request. Depends on: CLI core.

- [ ] **v0.2: Share Extension** (M) — requires migrating storage to an app-group
  container (v0.1 deliberately uses plain Application Support). Trigger: v0.2.

- [ ] **v0.2: Full-page archiving + local semantic search** (L) — the Pipeline has
  reserved slots. Semantic-search backend decision (NLEmbedding vs CoreML MiniLM vs
  BYOK) after v0.1 usage data.

## P3 — demand-driven

- [ ] **E6: `cap serve` Pinboard-compatible localhost API** (M) — revisit when a
  third-party client wants it; needs auth-token design.

- [ ] **Trigram FTS table** (S) — add as a migration when a real substring query is
  slow (~100k captures). v0.1 ships porter-only FTS + indexed LIKE fallback.

- [ ] **Sparkle in-app updates** (M) — only if direct-.dmg users materialize; brew
  tap covers the launch audience. Costs appcast hosting + EdDSA keys + cask drift.

- [ ] **Dedupe on re-capture** ("captured 3w ago" HUD variant) (S) — v0.1.x delight.

- [ ] **Paste-URL detection in search window** (S) — v0.1.x delight.

- [ ] **Homebrew core cask listing / naming question** — `cap` cask name is owned by
  cap.so (screen recorder). Personal tap (`jamiedavenport/tap/cap`) sidesteps it;
  reopen only if core listing is wanted.
