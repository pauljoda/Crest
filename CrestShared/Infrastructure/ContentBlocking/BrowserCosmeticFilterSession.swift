import Foundation

/// Answers a page's cosmetic bridge: what each of its documents hides beyond
/// what the page's engine blocks, as the core decides for the page's Space and
/// the site the page shows. The bridge posts as a document starts and as its
/// elements appear; the answer goes back to the document that asked. It also
/// runs the bridge's element picker in the top document for the page's picker
/// bar, and keeps what the person blocks with it as a rule of their own
/// filters.
@MainActor
final class BrowserCosmeticFilterSession {
    // MARK: - Types

    typealias Evaluate =
        @MainActor (_ body: String, _ arguments: [String: Any], _ frame: BrowserContentFrame) async throws -> Any?

    // MARK: - Static Variables

    /// The element kinds the bridge names, by its spelling.
    private static let kinds: [String: PageResourceKind] = ["frame": .frame, "image": .image, "object": .object]

    // MARK: - Variables

    private let core: CrestCore
    private let spaceID: UUID
    private let siteURL: @MainActor () -> URL?
    private let evaluate: Evaluate
    /// The page's element picker, which the bridge's reports update.
    private let picker: BrowserElementPicker
    /// The top document that last posted, where the picker runs.
    private var mainFrame: BrowserContentFrame?

    /// Whether Crest blocks at all, so a rule the picker writes would apply.
    var blocksContent: Bool { core.state.filterLists.level.blocksContent }

    // MARK: - Initializers

    init(
        core: CrestCore,
        spaceID: UUID,
        picker: BrowserElementPicker,
        siteURL: @escaping @MainActor () -> URL?,
        evaluate: @escaping Evaluate
    ) {
        self.core = core
        self.spaceID = spaceID
        self.picker = picker
        self.siteURL = siteURL
        self.evaluate = evaluate
        picker.send = { [weak self] command in self?.perform(command) }
    }

    // MARK: - Actions - Messages

    /// Answers one message from the bridge in `frame`'s document.
    func receive(_ body: Any, from frame: BrowserContentFrame) {
        guard let message = body as? [String: Any], let documentURL = message["url"] as? String,
            let site = siteURL(), ["http", "https"].contains(site.scheme?.lowercased() ?? "")
        else { return }
        if frame.isMainFrame {
            mainFrame = frame
            // A new top document has no picker running.
            if message["first"] as? Bool == true { picker.end() }
            if let report = message["picker"] as? [String: Any] { return picker.apply(report) }
            if let selector = message["block"] as? String {
                // Only what the running picker holds, as the bar shows it.
                guard picker.isActive, selector == picker.selector else { return }
                _ = try? core.send(BlockElement(pageURL: site.absoluteString, selector: selector))
                return
            }
        }
        let resources = (message["resources"] as? [[String: Any]] ?? []).compactMap(Self.resource)
        let query = DocumentCosmetics(
            spaceID: spaceID, siteURL: site.absoluteString, documentURL: documentURL,
            first: message["first"] as? Bool ?? false,
            classes: message["classes"] as? [String] ?? [], ids: message["ids"] as? [String] ?? [],
            resources: resources)
        guard let answer = try? core.query(query) else { return }
        // A blocking document with nothing new to hide needs no answer.
        if answer.blocks, answer.style.isEmpty, answer.procedural.isEmpty, answer.collapse.isEmpty,
            !(message["first"] as? Bool ?? false)
        {
            return
        }
        let reply: [String: Any] = [
            "blocks": answer.blocks, "style": answer.style,
            "procedural": answer.procedural, "collapse": answer.collapse,
        ]
        let evaluate = evaluate
        Task { _ = try? await evaluate(BrowserCosmeticFilterContentBridge.applyBody, ["answer": reply], frame) }
    }

    /// An element the bridge named, or nil for one it named oddly.
    private static func resource(_ named: [String: Any]) -> PageResource? {
        guard let kind = (named["kind"] as? String).flatMap({ kinds[$0] }), let url = named["url"] as? String else {
            return nil
        }
        return PageResource(kind: kind, url: url)
    }

    // MARK: - Actions - Picker

    /// Starts the element picker in the page's top document, from what the
    /// person last right-clicked when `fromContextMenu`. Answers whether it
    /// started, which it cannot before the document's bridge first posts.
    func pickElement(fromContextMenu: Bool) async -> Bool {
        guard let mainFrame else { return false }
        let options = BrowserCosmeticFilterContentBridge.pickerOptions(fromContextMenu: fromContextMenu)
        let started = try? await evaluate(BrowserCosmeticFilterContentBridge.pickBody, ["options": options], mainFrame)
        return started as? Bool ?? false
    }

    /// Gives the running picker the bar's `command`.
    private func perform(_ command: BrowserElementPicker.Command) {
        guard let mainFrame else { return }
        let evaluate = evaluate
        Task {
            _ = try? await evaluate(
                BrowserCosmeticFilterContentBridge.pickerCommandBody, ["command": command.rawValue], mainFrame)
        }
    }
}
