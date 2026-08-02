# cap

An open-source native macOS capture and bookmarking app — one hotkey to save what you are
looking at, one hotkey to find it again.

> **TODO(E4):** the one-line "why this instead of Linkding or Anybox?" positioning, the
> capture-to-recall demo GIF, and the install instructions land before the v0.1 tag.

**Status: scaffold.** The package builds and the four targets link, but no capture, storage,
or search exists yet. See `docs/designs/cap-v0.1.md` for the architecture and `TODOS.md` for
deferred scope.

## Layout

| Target | What it is |
| --- | --- |
| `CapKit` | The brains: data model, store, capture pipeline, search. A library, so the clients stay thin. |
| `CapCLI` | The `cap` binary — scriptable from day one. |
| `CapAgent` | The `cap-agent` background enrichment worker (page fetch, extraction, OCR). |
| `CapApp` | The menu-bar app: capture HUD, search window, settings. |

## Development

Requires macOS 26 and Xcode 26.3.

```sh
./Scripts/bootstrap.sh   # once per clone — enables the formatting pre-commit hook
swift build
swift test
```

`bootstrap.sh` points `core.hooksPath` at `.githooks`, which formats staged Swift files on
commit. It is opt-in because git never runs hooks straight from a clone; CI runs
`swift format lint --strict` regardless.

## License

MIT — see [LICENSE](LICENSE).
