# cap

Open-source native macOS capture/bookmarking app — the Pinboard successor.

# Linear

- Use Linear's branch names so that PRs are automatically linked.

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
- Roadmap belongs in Linear or Github issues.
- Architecture belongs in `docs/designs/`.

# READMEs

- Describe what exists, in the present tense.
- If a section can only be written in the future tense, leave it out.
