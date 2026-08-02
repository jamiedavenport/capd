# cap

An open-source native macOS capture and bookmarking app.

## Layout

- `CapKit` — library holding the data model, store, capture pipeline, and search
- `CapCLI` — the `cap` binary
- `CapAgent` — the `cap-agent` background enrichment worker
- `CapApp` — the menu-bar app

## CLI

```sh
cap add https://example.com/article      # capture a link; the page fetch is queued
cap add https://example.com --no-fetch   # capture the link only
cap add "remember this" --note "why"     # capture text
pbpaste | cap add -                      # capture stdin; URL-only lines each become a capture
cap add https://example.com --wait       # block until enrichment finishes

cap search swift concurrency --site swift.org --since 2026-01-01 --until 2026-06-30
cap list
cap rm 12
cap export --format markdown             # or json, which carries every stored field
cap refetch                              # requeue failed enrichments; or: cap refetch 12
```

Read commands take `--json` and `--format tsv`. The `--json` field set is a stable
interface for scripts; human-readable output is not. Exit codes: 0 success, 1 no
results, 2 bad usage, 3 store unavailable, 4 agent not running. `CAP_DIR` overrides
the storage root (default `~/Library/Application Support/cap/`).

## Development

Requires macOS 26 and Xcode 26.3.

```sh
./Scripts/bootstrap.sh   # once per clone
swift build
swift test
```

`bootstrap.sh` resolves dependencies and points `core.hooksPath` at `.githooks`, which
formats staged Swift files on commit. CI runs `swift format lint --strict` regardless.
Conductor workspaces run it automatically via `.conductor/settings.toml`.

## License

MIT — see [LICENSE](LICENSE).
