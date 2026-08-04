# Auto tagging

Every capture carries one to three topic tags from a global taxonomy capped at ten.
Tags are assigned on-device by Apple's Foundation Models, arrive a few seconds after
a capture finishes enrichment, and the taxonomy itself evolves as the library grows.

## Storage

Tags live on `captures` as a space-joined lowercase `tags` TEXT column plus a
`tags_version` integer. Version 0 means "not yet processed"; a positive version with
NULL tags means "processed, nothing applied" — the distinction is what keeps
untaggable captures from being retried forever. The `tags` column is part of the FTS5
index (weighted like `host`), so tag words match free-text queries too.

The taxonomy is a single row in the `taxonomy` table: the ordered tag list, a
`version`, a `tagged_since_consolidation` counter, and the `tagging_enabled` flag.
The flag lives in the database rather than `UserDefaults` because `capd-agent` — a
separate binary — has to obey it. A `retag_requested` flag carries the manual
Retag All action across the same process boundary, and `retag_in_progress` keeps
that full-library pass on a fixed vocabulary across agent polls.

## Single writer

Tagging does not use the enrichment pipeline's claim protocol. `capd-agent` already
holds an exclusive flock per store, so it is the only process that assigns tags or
revises the taxonomy; the app only changes the enabled and retag-request controls,
and the CLI is a pure reader. That makes the
`tags_version = 0` scan race-free without any claim machinery, and keeps model
inference off the app's interactive path. `TagService` itself is process-agnostic —
if Foundation Models ever proves unusable from a launchd agent, the same service can
run from the app on a timer.

## Assignment

Each agent tick tags a small batch (three on mains power, one on battery) of
captures in a terminal enrichment state, oldest first, so tagging sees the extracted
body or OCR text. One fresh `LanguageModelSession` per capture — the on-device
context window is small — with the current taxonomy in the instructions and a
bounded excerpt in the prompt. The model's candidates are never trusted: they are
normalized (lowercase, hyphenated, diacritics folded), deduplicated, and dropped
unless they are in the taxonomy or there is room to grow it (up to ten, only while
under the cap). Guardrail violations, model refusals, and unsupported languages mark
the capture processed-with-no-tags rather than letting it hot-loop. Transient failures
leave it queued and use an exponential retry delay capped at five minutes.

## Consolidation

Every 25 ordinary taggings — or whenever more distinct tags are in use than the cap allows —
one model call reviews per-tag usage (counts plus sample titles) and proposes which
tags to keep and how to fold the rest in. Applying the revision is mechanical: a
rename map over the rows in batched write transactions, so the sweep costs one model
call regardless of library size. A planned full-library retag starts this counter over
and does not advance it. Captures left with no surviving tags reset to
version 0 and are re-tagged incrementally under the new vocabulary. The sweep runs
only on mains power.

## Surfaces

- Search rows show up to two tag chips; Tab / Shift+Tab cycles the tags as filters,
  most used first, with "all captures" as the stop between the ends. The cycled tag
  is appended to the query as a trailing `tag:` token, so filtering reuses the query
  parser and both search legs; typing clears it.
- `tag:` is query syntax everywhere search runs, and `capd search --tag` is the flag
  form. Matching is whole-token: `tag:swift` never matches `swiftui`.
- Tags flow through `capd export --json` with the rest of the capture fields.
- The settings toggle writes through to the store and disables itself, with the
  reason, when Apple Intelligence is off or unavailable.
- The Retag All settings action records a request in the taxonomy row. The agent first
  samples captures evenly across the library and plans a coherent global vocabulary.
  It then atomically installs that vocabulary, clears automatic assignments, and works
  through them without inventing new tags. Imported pinned tags are preserved.
