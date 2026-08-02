# cap

Open-source native macOS capture/bookmarking app — the Pinboard successor.
Design doc: ~/.gstack/projects/cap/jamie-main-design-20260802-134500.md

# Linear

- Use Linear's branch names so that PRs are automatically linked.

## gstack

- Use the /browse skill from gstack for all web browsing. NEVER use `mcp__claude-in-chrome__*` tools.
- Available gstack skills: /office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /connect-chrome, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /setup-gbrain, /retro, /investigate, /document-release, /document-generate, /codex, /cso, /autoplan, /plan-devex-review, /devex-review, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade, /learn

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec

# Comments

- Comments are a cost. Default to none.
- Write one only to explain **why** — a workaround, constraint, or deliberate trade-off the code can't convey.
- Or as a `///` doc comment on public API.
- If a comment is needed to make code understandable, rename or restructure first.
- Never restate what the code does, narrate what a file will contain later, or justify an import or dependency.

# External state

- Never reference Linear IDs, ticket codes, or decision labels (`A5`, `T9`, `X1`) in source, config, or docs.
- Never add `TODO(TICKET)`, "coming in v0.2", or "Status: scaffold".
- These go stale silently and can't be verified from the codebase.
- Rationale belongs in commit messages and PR descriptions.
- Roadmap belongs in Linear or `TODOS.md`.
- Architecture belongs in `docs/designs/`.

# READMEs

- Describe what exists, in the present tense.
- If a section can only be written in the future tense, leave it out.
