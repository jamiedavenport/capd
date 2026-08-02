# cap

An open-source native macOS capture and bookmarking app.

## Layout

- `CapKit` — library holding the data model, store, capture pipeline, and search
- `CapCLI` — the `cap` binary
- `CapAgent` — the `cap-agent` background enrichment worker
- `CapApp` — the menu-bar app

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
retryable.

Article extraction uses Mozilla's [Readability.js](https://github.com/mozilla/readability)
with [SwiftSoup](https://github.com/scinfu/SwiftSoup) as the fallback — see
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).

## License

MIT — see [LICENSE](LICENSE).
