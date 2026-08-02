# Capture-accuracy matrix

Manual pre-dogfood verification that hotkey capture lands the right title, URL, and
selection on every supported surface, that unsupported surfaces degrade honestly, and
that the secure-input refusal is visible.

**Run date:** _pending_
**App build (commit):** _pending_
**macOS:** _pending_
**Result key:** ✅ pass · ⚠️ pass with notes · ❌ fail

## How to verify a capture

After each hotkey press, inspect the newest capture:

```sh
cap list --json | head -40
```

Fields that matter per cell: `title`, `url`, `selection`, `kind`,
`source_app_bundle_id`, `body_source` (`tab` = read from the browser tab,
`fetch` = network fallback). For blocked cases, confirm no new row exists at all.

To check the clipboard-restore cases, put a distinctive string on the clipboard
before capturing and paste it somewhere afterwards.

## 1. Scriptable browsers — Safari, Chrome, Arc

Expected: title + URL from the tab reader, selection from Accessibility,
`body_source = tab`, HUD "Captured". With nothing selected, the ⌘C fallback fires,
finds nothing, and the capture is link-only with the clipboard left intact.

| # | Browser | Case | Expected | Result | Notes |
|---|---------|------|----------|--------|-------|
| 1 | Safari | Paragraph selected on article page | title+URL+selection, `body_source=tab` | | |
| 2 | Safari | No selection | title+URL only, clipboard untouched | | |
| 3 | Safari | Distinctive clipboard, no selection | capture ok, clipboard restored verbatim | | |
| 4 | Chrome | Paragraph selected on article page | title+URL+selection, `body_source=tab` | | |
| 5 | Chrome | No selection | title+URL only, clipboard untouched | | |
| 6 | Chrome | Distinctive clipboard, no selection | capture ok, clipboard restored verbatim | | |
| 7 | Arc | Paragraph selected on article page | title+URL+selection, `body_source=tab` | | |
| 8 | Arc | No selection | title+URL only, clipboard untouched | | |
| 9 | Arc | Distinctive clipboard, no selection | capture ok, clipboard restored verbatim | | |

## 2. Firefox — degraded path

Firefox has no tab extraction, so a capture must not pretend otherwise: no fabricated
or stale URL/title, selection arrives via Accessibility or ⌘C as a text capture with
`source_app_bundle_id = org.mozilla.firefox`.

| # | Case | Expected | Result | Notes |
|---|------|----------|--------|-------|
| 10 | Paragraph selected | text capture, correct bundle id, **no** URL/title claiming to be from the tab | | |
| 11 | No selection | ⌘C fallback; text-less outcome handled cleanly, no junk row | | |

## 3. Electron app

No dedicated code path exists; this section records the emergent behavior. Use
Visual Studio Code or Slack. Note in each row whether Accessibility or the ⌘C
fallback provided the text.

| # | Case | Expected | Result | Notes |
|---|------|----------|--------|-------|
| 12 | Text selected in Electron app | text capture, correct `source_app_bundle_id`, no URL | | |
| 13 | No selection | clean no-capture or link-less outcome, clipboard intact | | |

## 4. PDF viewers

| # | Case | Expected | Result | Notes |
|---|------|----------|--------|-------|
| 14 | Preview.app, text selected in a PDF | text capture via AX or ⌘C, no URL | | |
| 15 | PDF open in a Safari/Chrome tab | title+URL land; tab HTML is useless so `body_source=fetch` | | |

## 5. ⌘C fallback edge cases

The pasteboard snapshot refuses to run the synthetic ⌘C when it cannot guarantee a
restore. The HUD downgrades to "Captured link only" with a reason line.

| # | Case | Expected | Result | Notes |
|---|------|----------|--------|-------|
| 16 | File copied in Finder (promised content), then capture with no selection | HUD "Captured link only" + "the clipboard holds promised files cap can't restore"; no ⌘C posted | | |
| 17 | >10 MB on clipboard (large image), then capture with no selection | HUD "Captured link only" + "the clipboard is too large to restore safely" | | |
| 18 | Image copied via real selection | image capture stored as PNG | | |

## 6. Secure fields — refusal is visible

| # | Case | Expected | Result | Notes |
|---|------|----------|--------|-------|
| 19 | Focus in a web password field, hotkey | HUD "Capture blocked" / "Secure input is active." (orange lock); no row written | | |
| 20 | Terminal with Secure Keyboard Entry on, capture from any app | same blocked HUD; no row written | | |

## Findings

_pending — anything ❌ or surprising above gets a line here and a tracking issue._
