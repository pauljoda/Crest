import AppKit
import Observation
import SwiftUI

/// Native presentation state only. Installation, permissions, pinning, workers,
/// and package storage remain owned by Chromium's independent Space profiles.
@Observable @MainActor
final class ChromiumExtensionStore {
    struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String
        let detail: String
        let icon: NSImage?
        let enabled: Bool
        let permissions: [String]
        let webStore: Bool
        let options: String
        init(_ item: [String: Any]) {
            id = item["id"] as? String ?? ""
            name = item["name"] as? String ?? id
            version = item["version"] as? String ?? ""
            detail = item["description"] as? String ?? ""
            icon = item["icon"] as? NSImage
            enabled = item["enabled"] as? Bool ?? true
            permissions = item["permissions"] as? [String] ?? []
            webStore = item["webStore"] as? Bool ?? true
            options = item["options"] as? String ?? ""
        }
        var permissionIdentity: [String] { [id, version] + permissions.sorted() }
    }
    var revision = 0
    private(set) var installed: [UUID: [Installed]] = [:]
    private(set) var installation: ChromiumExtensionInstallation?
    @ObservationIgnored private var popover: NSPopover?
    @ObservationIgnored private var windowClosed: NSObjectProtocol?
    /// The one-point view the install review is anchored to. It belongs to the
    /// window's own hosting view and is removed with the review.
    @ObservationIgnored private var anchorSpot: NSView?
    /// Runs when the presented install operation ends, however it ended. The
    /// Chrome Web Store listing that started it uses this to restate its own
    /// button instead of leaving it in the progress label.
    @ObservationIgnored private var installCompletion: (@MainActor () -> Void)?

    var spaces: [BrowserSpace] { CrestChromiumRoot.extensionSpaces }
    /// Whether this Space's engine profile may be read and prepared here.
    ///
    /// Ownership is decided by `(spaceID, profileID)` against the store family
    /// that owns the window asking, not by identity against one global list: a
    /// window's own store publishes its Spaces before the application-wide list
    /// a start-up read would see. A Space from an unrelated family — another
    /// family's window, a borrowed settings workspace, a private window, which
    /// has no persistent engine profile of its own — and a locked Space are all
    /// refused. Callers with no window fall back to the application list.
    func authorized(_ space: BrowserSpace, in browser: BrowserStore? = nil) -> Bool {
        guard !CrestChromiumRoot.isSpaceLocked(space) else { return false }
        guard let browser else {
            return spaces.contains { $0.id == space.id && $0.profile.id == space.profile.id }
        }
        guard CrestChromiumRoot.ownsExtensionProfiles(browser) else { return false }
        return browser.space(matching: BrowserSpaceRuntimeAssignment(space: space)) != nil
    }
    func refresh() {
        revision &+= 1
        guard let host = CrestChromiumRoot.engineHost else { return }
        let profiles = Set(spaces.map { $0.profile.id })
        installed = installed.filter { profiles.contains($0.key) }
        for space in spaces where installed[space.profile.id] != nil {
            installed[space.profile.id] = host.extensions(forProfile: space.profile.id.uuidString).map(Installed.init)
        }
    }
    func load(_ space: BrowserSpace, in browser: BrowserStore? = nil) async {
        guard authorized(space, in: browser), let host = CrestChromiumRoot.engineHost else { return }
        let ready = await withCheckedContinuation { continuation in
            host.prepareExtensionProfile(space.profile.id.uuidString) { ready in continuation.resume(returning: ready) }
        }
        guard ready, authorized(space, in: browser) else { return }
        installed[space.profile.id] = host.extensions(forProfile: space.profile.id.uuidString).map(Installed.init)
        revision &+= 1
    }
    func actions(for page: ChromiumNativePage) -> [BrowserExtensionActionPresentation] {
        _ = revision
        return page.extensions.map {
            BrowserExtensionActionPresentation(id: $0.id, displayName: $0.name, badgeText: $0.badge,
                icon: $0.icon, isPinned: $0.pinned)
        }
    }
    /// The pinned actions of a Space's own toolbar row.
    ///
    /// The row belongs to the Space, so the pinned list comes from the Space's
    /// profile and is present whether or not a page is open. Where a page is
    /// open its per-tab state — badge, dynamic icon, whether a page action has
    /// anything to act on — is overlaid on top of it.
    func pinnedActions(for space: BrowserSpace, page: ChromiumNativePage?) -> [BrowserExtensionActionPresentation] {
        _ = revision
        guard let host = CrestChromiumRoot.engineHost else { return [] }
        let live = Dictionary(page?.extensions.map { ($0.id, $0) } ?? [],
                              uniquingKeysWith: { first, _ in first })
        return host.pinnedExtensions(profile: space.profile.id.uuidString)
            .compactMap { item -> BrowserExtensionActionPresentation? in
                guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
                if let tab = live[id] {
                    return BrowserExtensionActionPresentation(id: id, displayName: tab.name,
                        badgeText: tab.badge, icon: tab.icon, isPinned: true)
                }
                return BrowserExtensionActionPresentation(id: id, displayName: name,
                    badgeText: item["badge"] as? String ?? "", icon: item["icon"] as? NSImage,
                    isEnabled: item["enabled"] as? Bool ?? true, isPinned: true)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    /// Runs a pinned action from a Space with no page open. Only an action with
    /// its own popup can run without one, so anything else states itself as
    /// unavailable rather than doing nothing.
    func runPinned(_ action: BrowserExtensionActionPresentation, space: BrowserSpace,
                   anchor: BrowserExtensionPopupAnchor?) {
        let fallback = CrestChromiumRoot.activeNativeWindow
        let anchor = anchor ?? BrowserExtensionPopupAnchor(screenPoint: NSEvent.mouseLocation,
                                                          sourceWindow: fallback)
        guard let host = CrestChromiumRoot.engineHost,
              let source = anchor.presentationSource(fallbackWindow: fallback),
              let windowID = source.view.window?.identifier?.rawValue,
              host.runExtension(action.id, profile: space.profile.id.uuidString, window: windowID,
                                anchorView: source.view, anchorRect: source.rect) else {
            CrestChromiumRoot.showNativeNotice(
                String(localized: "This extension action needs an open page."),
                icon: "puzzlepiece.extension")
            return
        }
    }
    /// Makes sure the Space's engine profile is loaded so its pinned list can be
    /// read before anything has been opened in it.
    ///
    /// Idempotent: the Space keeps whatever the engine reported, so the row can
    /// ask on every appearance and every Space change. A Space the window's own
    /// store does not own — a private window's, a borrowed workspace's — is left
    /// alone; its profile exists only while a page of its own does.
    func prepare(_ space: BrowserSpace, in browser: BrowserStore? = nil) async {
        guard installed[space.profile.id] == nil, authorized(space, in: browser) else { return }
        await load(space, in: browser)
    }
    @discardableResult
    func command(_ command: String, extensionID: String = "", space: BrowserSpace, window: NSWindow? = nil) -> Bool {
        guard authorized(space), let host = CrestChromiumRoot.engineHost,
              let window = window ?? CrestChromiumRoot.activeNativeWindow,
              let windowID = window.identifier?.rawValue else { return false }
        let destination: String?
        switch command {
        case "store": destination = extensionID.isEmpty
            ? "https://chromewebstore.google.com/"
            : "https://chromewebstore.google.com/detail/\(extensionID)"
        case "manage": destination = "chrome://extensions/"
        case "shortcuts": destination = "chrome://extensions/shortcuts"
        case "details": destination = "chrome://extensions/?id=\(extensionID)"
        case "options": destination = installed[space.profile.id]?.first { $0.id == extensionID }?.options
        default: destination = nil
        }
        if let destination, let url = URL(string: destination) {
            return CrestChromiumRoot.openExtensionURL(url, in: space, window: window)
        }
        let accepted = host.extensionCommand(command, extension: extensionID,
            profile: space.profile.id.uuidString, window: windowID)
        refresh()
        return accepted
    }
    func togglePin(_ action: BrowserExtensionActionPresentation, space: BrowserSpace) {
        _ = command(action.isPinned ? "unpin" : "pin", extensionID: action.id, space: space)
    }
    /// Reports the installed record backing an action so the menu can offer only
    /// the verbs the extension actually supports. The profile is already prepared
    /// whenever an action is presented, so the host answers synchronously.
    private func installedRecord(_ extensionID: String, in space: BrowserSpace) -> Installed? {
        if let cached = installed[space.profile.id] { return cached.first { $0.id == extensionID } }
        guard authorized(space), let host = CrestChromiumRoot.engineHost else { return nil }
        let items = host.extensions(forProfile: space.profile.id.uuidString).map(Installed.init)
        guard !items.isEmpty else { return nil }
        installed[space.profile.id] = items
        revision &+= 1
        return items.first { $0.id == extensionID }
    }
    /// - Parameter openSidePanel: Supplied only when the extension has a side
    ///   panel entry for the page the action was presented on. The caller owns
    ///   the window the panel would mount into, so it also owns the check.
    func presentMenu(_ action: BrowserExtensionActionPresentation, space: BrowserSpace,
                     anchor: BrowserExtensionPopupAnchor?, isPrivate: Bool = false,
                     openSidePanel: (@MainActor () -> Void)? = nil) {
        let menu = NSMenu(title: action.displayName)
        menu.autoenablesItems = false
        let handler = ExtensionMenuHandler()
        let record = installedRecord(action.id, in: space)
        if let openSidePanel {
            menu.addItem(handler.item(String(localized: "Open Side Panel")) { openSidePanel() })
            menu.addItem(.separator())
        }
        // A private window must never change the Space's persistent extension
        // state, so only the navigation verbs are offered from one.
        if !isPrivate {
            if record.map({ !$0.options.isEmpty && $0.enabled }) ?? true {
                menu.addItem(handler.item(String(localized: "Extension Settings…")) { [weak self] in
                    self?.command("options", extensionID: action.id, space: space)
                })
            }
            menu.addItem(handler.item(action.isPinned
                ? String(localized: "Unpin from Toolbar") : String(localized: "Pin to Toolbar")) { [weak self] in
                self?.togglePin(action, space: space)
            })
            if let record {
                menu.addItem(handler.item(record.enabled
                    ? String(localized: "Disable Extension") : String(localized: "Enable Extension")) { [weak self] in
                    self?.command(record.enabled ? "disable" : "enable", extensionID: action.id, space: space)
                })
            }
            menu.addItem(.separator())
        }
        menu.addItem(handler.item(String(localized: "Manage Extension…")) { [weak self] in
            self?.command("details", extensionID: action.id, space: space)
        })
        menu.addItem(handler.item(String(localized: "Manage Extensions…")) { [weak self] in
            self?.command("manage", space: space)
        })
        if record?.webStore ?? false {
            menu.addItem(handler.item(String(localized: "View on Chrome Web Store")) { [weak self] in
                self?.command("store", extensionID: action.id, space: space)
            })
        }
        if !isPrivate, let record {
            menu.addItem(.separator())
            menu.addItem(handler.item(String(localized: "Remove Extension…")) { [weak self] in
                self?.confirmRemoval(record, space: space)
            })
        }
        if let source = anchor?.presentationSource(fallbackWindow: CrestChromiumRoot.activeNativeWindow) {
            menu.popUp(positioning: nil, at: NSPoint(x: source.rect.minX, y: source.rect.minY), in: source.view)
        } else { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
        withExtendedLifetime(handler) {}
    }
    /// Removal asked for by identifier — the Chrome Web Store listing for an
    /// extension already installed in this Space. The confirmation, the Space's
    /// ownership check and the engine command are the menu's own.
    func confirmRemoval(_ extensionID: String, in space: BrowserSpace,
                        completion: (@MainActor () -> Void)? = nil) {
        guard let record = installedRecord(extensionID, in: space) else {
            completion?()
            return
        }
        confirmRemoval(record, space: space, completion: completion)
    }
    /// Mirrors the confirmation the extension settings pane requires before an
    /// uninstall. The menu's tracking loop owns the event while an item runs, so
    /// the alert is presented once the menu has dismissed.
    private func confirmRemoval(_ record: Installed, space: BrowserSpace,
                                completion: (@MainActor () -> Void)? = nil) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.authorized(space) else { completion?(); return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Remove \(record.name)?")
            alert.informativeText = String(localized:
                "\(record.name) and its Space-local data will be removed. Other Spaces are unchanged.")
            alert.addButton(withTitle: String(localized: "Remove from \(space.name)"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.buttons.first?.hasDestructiveAction = true
            let complete: (NSApplication.ModalResponse) -> Void = { response in
                MainActor.assumeIsolated {
                    defer { completion?() }
                    guard response == .alertFirstButtonReturn else { return }
                    guard self.command("remove", extensionID: record.id, space: space) else {
                        self.reportFailure(); return
                    }
                }
            }
            if let window = CrestChromiumRoot.activeNativeWindow {
                alert.beginSheetModal(for: window, completionHandler: complete)
            } else {
                complete(alert.runModal())
            }
        }
    }
    private func reportFailure() {
        BrowserNoticeCenter.shared.post(BrowserNotice(
            message: String(localized: "Couldn’t complete that extension action. Check its details for policy or permission requirements."),
            systemImage: "exclamationmark.triangle"))
    }
    func install(_ id: String, in space: BrowserSpace, anchor: NSView?, copies: Set<SpaceID> = [],
                 completion: (@MainActor () -> Void)? = nil) {
        guard installation == nil, authorized(space),
              let window = anchor?.window ?? CrestChromiumRoot.activeNativeWindow else {
            completion?()
            return
        }
        installCompletion = completion
        let job = ChromiumExtensionInstallation(id: id, space: space, window: window, store: self)
        job.selectedSpaces = copies
        installation = job
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: BrowserChromeWebStoreInstallView(model: job))
        self.popover = popover
        // Anchor native presentation in Crest's hosting view. Anchoring it in
        // Chromium's responder subtree lets web focus consume popover input.
        guard let source = window.contentView else { dismissInstallation(); return }
        // AppKit reads a caller's positioning rectangle as if the view were not
        // flipped, and SwiftUI's hosting view is flipped: a rectangle measured
        // from its top edge presented the review past the window's lower edge
        // and off the screen. A one-point positioning view carries the anchor
        // instead, because a subview's own frame is resolved in its superview's
        // coordinate space whichever way that space runs.
        let spot = NSView(frame: NSRect(x: min(160, source.bounds.width / 2),
            y: source.isFlipped ? 44 : source.bounds.height - 44, width: 1, height: 1))
        source.addSubview(spot)
        anchorSpot = spot
        popover.show(relativeTo: .zero, of: spot, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        windowClosed = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissInstallation() }
        }
        Task { await job.start() }
    }
    func review(_ values: [String: Any], window: NSWindow, reply: @escaping (Bool, Bool) -> Void) {
        guard let job = installation, job.window === window, values["id"] as? String == job.id else {
            // No user-owned install operation may inherit an unrelated consent.
            reply(false, false)
            return
        }
        job.review(values, reply: reply)
    }
    func dismissInstallation() {
        installation?.cancel()
        installation = nil
        popover?.close()
        popover = nil
        if let windowClosed { NotificationCenter.default.removeObserver(windowClosed) }
        windowClosed = nil
        anchorSpot?.removeFromSuperview()
        anchorSpot = nil
        let completion = installCompletion
        installCompletion = nil
        completion?()
    }
}

/// Owns the menu item closures; `NSMenuItem.target` is weak, so this has to
/// outlive the menu's tracking loop.
@MainActor private final class ExtensionMenuHandler: NSObject {
    private var handlers: [() -> Void] = []
    func item(_ title: String, perform: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        item.tag = handlers.count
        handlers.append(perform)
        return item
    }
    @objc private func invoke(_ sender: NSMenuItem) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}

@Observable @MainActor
final class ChromiumExtensionInstallation {
    let id: String
    let space: BrowserSpace
    weak var window: NSWindow?
    private let store: ChromiumExtensionStore
    var candidate: ChromiumExtensionStore.Installed?
    var selectedSpaces: Set<SpaceID> = []
    var withhold = false
    var canWithhold = false
    var preparing = true
    var installing = false
    var completed = false
    var installedCount = 0
    var failure: String?
    var canAccept = false
    @ObservationIgnored private var consent: ((Bool, Bool) -> Void)?
    @ObservationIgnored private var approvedIdentity: [String]?
    @ObservationIgnored private var approvedDestinations: [BrowserSpace] = []
    @ObservationIgnored private var package: URL?
    @ObservationIgnored private var canceled = false
    @ObservationIgnored private var targetSpace: BrowserSpace?

    init(id: String, space: BrowserSpace, window: NSWindow, store: ChromiumExtensionStore) {
        self.id = id; self.space = space; self.window = window; self.store = store
    }
    var isAuthorized: Bool { store.authorized(space) && (targetSpace.map { store.authorized($0) } ?? true) }
    var destinations: [BrowserSpace] {
        store.spaces.filter { $0.id != space.id && !(store.installed[$0.profile.id] ?? []).contains { $0.id == id } }
    }
    func start() async {
        for target in store.spaces { await store.load(target) }
        guard !canceled, let host = CrestChromiumRoot.engineHost else { return }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
            components.queryItems = [URLQueryItem(name: "response", value: "redirect"),
                URLQueryItem(name: "prodversion", value: host.engineVersion()),
                URLQueryItem(name: "acceptformat", value: "crx3"),
                URLQueryItem(name: "x", value: "id=\(id)&installsource=ondemand&uc")]
            var request = URLRequest(url: components.url!); request.timeoutInterval = 120
            let (file, response) = try await session.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 64 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            let retained = FileManager.default.temporaryDirectory.appendingPathComponent("crest-extension-\(UUID()).crx")
            try FileManager.default.moveItem(at: file, to: retained)
            package = retained
            defer { try? FileManager.default.removeItem(at: retained); package = nil }
            guard !canceled else { return }
            try await installPackage(in: space)
            installedCount = 1
            // Freeze the explicitly reviewed targets and package; every copy is
            // independently verified by Chromium and keeps its own profile data.
            for target in approvedDestinations {
                guard !canceled else { return }
                try await installPackage(in: target)
                installedCount += 1
            }
            completed = true
            store.refresh()
        } catch {
            if !canceled { failure = error.localizedDescription }
        }
        preparing = false; installing = false
    }
    private func installPackage(in target: BrowserSpace) async throws {
        guard !canceled, store.authorized(target), let package, let host = CrestChromiumRoot.engineHost,
              let windowID = window?.identifier?.rawValue else { throw URLError(.cancelled) }
        targetSpace = target
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("crest-extension-\(UUID()).crx")
        try FileManager.default.copyItem(at: package, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        let result: (Bool, String) = await withCheckedContinuation { continuation in
            if !host.installExtension(id, package: staged.path, profile: target.profile.id.uuidString, window: windowID, completion: { success, message in
                continuation.resume(returning: (success, message))
            }) { continuation.resume(returning: (false, "The Space is no longer available.")) }
        }
        guard result.0 else { throw NSError(domain: "CrestExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: result.1.isEmpty ? "Installation canceled." : result.1]) }
    }
    func review(_ values: [String: Any], reply: @escaping (Bool, Bool) -> Void) {
        guard !canceled, store.authorized(space), let targetSpace, store.authorized(targetSpace) else { reply(false, false); return }
        let candidate = ChromiumExtensionStore.Installed(values)
        if let approvedIdentity {
            // Consent applies only to the same verified package and warnings.
            reply(candidate.permissionIdentity == approvedIdentity, withhold)
            return
        }
        self.candidate = candidate
        canWithhold = values["canWithhold"] as? Bool ?? false
        withhold = values["withhold"] as? Bool ?? false
        consent = reply
        preparing = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.canAccept = true
        }
    }
    func accept() {
        guard canAccept, let candidate, store.authorized(space), let consent else { return }
        approvedIdentity = candidate.permissionIdentity
        approvedDestinations = destinations.filter { selectedSpaces.contains($0.id) }
        self.consent = nil
        installing = true
        consent(true, withhold)
    }
    func cancel() {
        canceled = true
        let callback = consent; consent = nil; callback?(false, false)
    }
    func dismiss() { store.dismissInstallation() }
}
