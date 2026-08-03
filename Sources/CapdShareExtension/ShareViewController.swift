import AppKit
import CapdHandoff
import UniformTypeIdentifiers

/// The share sheet entry: reads the shared page's URL, hands it to the app as a
/// `capd://capture` link, and completes without showing UI of its own — the app's HUD
/// is the feedback.
@objc(ShareViewController)
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            await handOff()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func handOff() async {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard
            let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            }),
            let page = await loadURL(from: provider)
        else { return }

        // Safari rides the page title in the extension item's content text; Chromium
        // browsers send the bare URL, and enrichment fills the title in later.
        let title = items.lazy
            .compactMap { $0.attributedTitle?.string ?? $0.attributedContentText?.string }
            .first
        let handoff = ShareHandoff.url(
            for: ShareHandoff.Payload(
                url: page.absoluteString,
                title: title,
                sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        guard let handoff else { return }
        await open(handoff)
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private func open(_ url: URL) async {
        guard let context = extensionContext else {
            NSWorkspace.shared.open(url)
            return
        }
        // NSExtensionContext.open is the sanctioned door out of an extension, but not
        // every host honors it; NSWorkspace is the fallback.
        let opened = await withCheckedContinuation { continuation in
            context.open(url) { continuation.resume(returning: $0) }
        }
        if !opened {
            NSWorkspace.shared.open(url)
        }
    }
}
