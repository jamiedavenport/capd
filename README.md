[![Capd](./banner.png)](https://capd.jxd.dev)

# Save anything. Find it in seconds.

Capd is a private, native macOS app for capturing the useful things you come
across—web pages, selected text, links, notes, and images—and finding them again
with full-text search.

No account. No subscription. No telemetry. Your library stays on your Mac.

[Download the latest release](https://github.com/jamiedavenport/capd/releases/latest)
· [Read the documentation](https://capd.jxd.dev)

<!--
MEDIA: capture-to-search.gif
Show a 10–15 second loop: select a useful paragraph in a browser, press ⌃⌥C,
see the capture HUD, then open search with ⌥⇧Space and find the page using a
phrase from its body. Keep the pointer still and make every keystroke readable.
-->

## Why Capd?

- **Capture without breaking focus.** Press `⌃⌥C`, drag something to the menu
  bar or notch, use the macOS share sheet, or run the `capd` CLI.
- **Search more than bookmarks.** Capd indexes page titles, readable article
  text, selections, notes, and text recognized inside images.
- **Stay organized automatically.** On-device tagging groups captures into a
  small, useful vocabulary without sending their contents anywhere.
- **Use your library everywhere.** Search in the native app, automate with the
  CLI, export your data, or give an AI assistant read-only access over MCP.
- **Keep control of your data.** Everything lives in a local SQLite database and
  assets folder. Network behavior is limited and documented in full.

## Install

Capd requires **macOS 26 or later** and supports Apple silicon and Intel Macs.

Download the notarized `.dmg` from the
[latest GitHub release](https://github.com/jamiedavenport/capd/releases/latest),
open it, and drag `capd.app` to Applications.

Or install the app and CLI with Homebrew:

```sh
brew install jamiedavenport/tap/capd
```

On first launch, Capd guides you through its hotkeys and optional macOS
permissions. Then press `⌃⌥C` anywhere to make your first capture and
`⌥⇧Space` to find it.

[See the installation guide](https://capd.jxd.dev/install) for permission,
update, and uninstall details.

## Capture your way

Capd saves links, selected text, clipboard images, and dropped files. Browser
captures include the current page and, where available, its readable content.
Image text is recognized on-device and becomes searchable.

Re-capturing the same item updates the existing entry instead of creating a
duplicate. Add a note from the confirmation HUD with `⌃⌥N`.

<!--
MEDIA: drag-to-capture.gif
Show a link and an image being dragged toward the MacBook notch. The HUD should
change to “Drop to capture,” accept each item, and confirm it without opening a
main window.
-->

[Explore every capture method](https://capd.jxd.dev/capture).

## Recall what matters

Press `⌥⇧Space` for fast, keyboard-first search across everything you saved.
Use natural keywords or narrow the results with site, tag, and date filters:

```text
swift concurrency site:swift.org tag:development after:2026-01-01
```

<!--
MEDIA: search-window.png
Show a populated search window with a short query, recognisable favicons,
useful result snippets, and several tag filters. Include a result matched from
page body text so the value goes beyond ordinary URL bookmarking.
-->

[Learn how search works](https://capd.jxd.dev/search).

## Built for the keyboard—and automation

The bundled `capd` command captures, searches, manages, and exports the same
local library:

```sh
capd add https://example.com/article
capd search "reading list" --site example.com
capd export --format markdown
capd mcp
```

`capd mcp` exposes read-only search tools to compatible AI assistants. The CLI
also provides stable JSON output for scripts.

[See the CLI reference](https://capd.jxd.dev/cli).

## Private by design

Capd has no account, cloud service, analytics, or telemetry. Page fetching,
favicon requests, update checks, OCR, and automatic tagging are documented in
the [privacy guide](https://capd.jxd.dev/privacy), including which network
features can be disabled.

Capd is open source under the [MIT License](LICENSE).

## Contributing

Want to build Capd, improve the docs, or send a patch? See
[CONTRIBUTING.md](CONTRIBUTING.md).
