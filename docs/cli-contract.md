# cap CLI contract

The `cap` binary is a scripting surface as much as a human one. This document defines
the parts of its behavior that scripts may rely on.

**Stable:** exit codes, the JSON output documented here, the TSV column set, and the
`CAP_DIR` environment variable. Stable fields are never renamed, retyped, or removed;
new JSON fields may be added, so consumers must ignore keys they do not recognize.

**Not stable:** plain (default) output, `doctor` output, markdown export, stderr
wording, and help text. These are for people, and change freely.

Data goes to stdout; diagnostics go to stderr.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success. |
| 1 | No results: an empty `search` or `list`, or an id passed to `rm` or `refetch` that does not exist, or `refetch` with nothing to requeue. Also `doctor` when a problem remains that it could not repair. |
| 2 | Bad usage: unknown command or flag, malformed value, or input that cannot be captured. |
| 3 | The capture store is unavailable (unreadable or uncreatable storage root). |
| 4 | The enrichment agent is not running: `status` found no live agent, or `add --wait` timed out with work still queued. |

Machine-readable output is emitted before the exit code is decided, so a `--json`
search with no hits still prints a valid empty array (`[]`) and then exits 1.

When a bulk `cap add -` partially fails, the successful captures are reported on
stdout, each failure goes to stderr, and the exit code is 2.

## Selecting a format

`search` and `list` take `--format plain|tsv|json`, defaulting to `plain`.
`export` takes `--format json|markdown`, defaulting to `json`.
`--json` is accepted by `add`, `search`, `list`, `export`, and `status` as shorthand
for JSON output and wins over `--format`.

## JSON output

Standard JSON, UTF-8, pretty-printed with keys sorted. Key names are `snake_case`.
Timestamps are ISO 8601 UTC with millisecond precision: `2026-03-03T00:00:00.500Z`.
Optional fields are omitted when unset, never emitted as `null`.

`search --json` and `list --json` print an array of hit objects:

| Key | Type | Presence | Meaning |
|-----|------|----------|---------|
| `capture` | object | always | The capture, documented below. |
| `snippet` | string | full-text hits only | A fragment of the matched text. |
| `score` | number | full-text hits only | Raw bm25 rank; lower is a better match. |

`add --json` prints the resulting captures (new or already existing) as an array of
capture objects, in input order. `export --format json` prints every capture the same
way and is the lossless backup format.

### The capture object

| Key | Type | Presence | Meaning |
|-----|------|----------|---------|
| `id` | integer | always | Row id, as shown by `list` and taken by `rm` and `refetch`. |
| `kind` | string | always | `link`, `text`, or `image`. |
| `url` | string | optional | The captured URL, normalized. |
| `host` | string | optional | Lowercased host of `url`. |
| `title` | string | optional | Page or user-supplied title. |
| `note` | string | optional | User-supplied note. |
| `selection` | string | optional | Captured text. |
| `body` | string | optional | Readable page body extracted for search. |
| `ocr_text` | string | optional | Text recognized in an image capture. |
| `asset_path` | string | optional | Image file path, relative to `$CAP_DIR/assets/`. |
| `source_app_bundle_id` | string | optional | Bundle id of the app the capture came from. |
| `enrichment_state` | string | always | `pending`, `fetching`, `ok`, `thin`, or `failed`. |
| `body_status` | string | always | `none`, `ok`, `thin`, or `failed`. |
| `body_source` | string | optional | `tab` or `fetch`. |
| `attempt_count` | integer | always | Enrichment attempts made so far. |
| `last_attempt_at` | timestamp | optional | When enrichment last ran. |
| `content_hash` | string | optional | Dedupe hash of the normalized URL or content. |
| `created_at` | timestamp | always | First capture time. |
| `updated_at` | timestamp | always | Last modification time. |
| `last_seen_at` | timestamp | always | Most recent re-capture of the same content. |
| `seen_count` | integer | always | Times this content has been captured. |

### The status report object

`status --json` prints a single object:

| Key | Type | Presence | Meaning |
|-----|------|----------|---------|
| `agent.installed` | boolean | always | The LaunchAgent plist is present. |
| `agent.loaded` | boolean | always | launchd has the agent label loaded. |
| `agent.running` | boolean | always | A live agent process holds this store's lock. False here is what makes `status` exit 4. |
| `captures.pending` | integer | always | Captures waiting for enrichment. |
| `captures.fetching` | integer | always | Captures being enriched right now. |
| `captures.ok` | integer | always | Captures whose enrichment succeeded. |
| `captures.thin` | integer | always | Captures whose enrichment came back thin. |
| `captures.failed` | integer | always | Captures whose enrichment failed. |
| `captures.total` | integer | always | All captures in the store. |
| `database_bytes` | integer | always | On-disk size of the database, WAL included. |
| `queue.depth` | integer | always | `pending + fetching`. |
| `queue.eta_seconds` | integer | non-empty queue only | Estimated seconds to drain the queue, from recent enrichment times and the current drain width. |

## TSV output

`--format tsv` prints one row per hit with no header, columns in this order:

```
id	created_at	kind	url	title	snippet
```

`created_at` uses the same UTC timestamp format as JSON. Absent values are empty
fields. Within a field, backslash, tab, newline, and carriage return are escaped as
`\\`, `\t`, `\n`, and `\r`, so rows and columns split cleanly on raw `\t` and `\n`.

## Environment

`CAP_DIR` overrides the storage root for the CLI, the app, and the agent alike
(default `~/Library/Application Support/cap/`).
