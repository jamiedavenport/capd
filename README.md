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
the storage root (default `~/Library/Application Support/cap/`). The full field set,
formats, and exit-code semantics are documented in
[docs/cli-contract.md](docs/cli-contract.md).

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

## Body extraction and the network

Link captures store the readable body of the page for search. When the capture comes from a
browser tab, cap reads the rendered page from that tab and nothing touches the network.
Otherwise cap fetches the URL itself, hardened as follows: http/https only, an ephemeral
`WKWebsiteDataStore` with no shared cookies, a 15-second timeout, a 10 MB cap, and navigation
locked to the target URL. Failed extractions keep the capture (title, URL, selection) and are
retryable. The fetch can be skipped per capture (`cap add --no-fetch`) or turned off entirely
in the app's settings.

Article extraction uses Mozilla's [Readability.js](https://github.com/mozilla/readability)
with [SwiftSoup](https://github.com/scinfu/SwiftSoup) as the fallback — see
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).

## Updates

The menu-bar app asks the GitHub Releases API for the latest version at most once a week. The
request carries nothing beyond the version lookup itself, and the check can be turned off in
the app's settings. When a newer release exists, an "Update available" menu item copies
`brew upgrade jamiedavenport/tap/cap` to the clipboard.

The page fetch above and this version check are the only network traffic cap produces.

## License

MIT — see [LICENSE](LICENSE).
