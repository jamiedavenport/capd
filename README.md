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

## License

MIT — see [LICENSE](LICENSE).
