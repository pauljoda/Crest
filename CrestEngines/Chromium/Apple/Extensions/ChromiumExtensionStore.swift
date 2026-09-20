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

    var spaces: [BrowserSpace] { CrestChromiumRoot.extensionSpaces }
    func authorized(_ space: BrowserSpace) -> Bool {
        spaces.contains { $0.id == space.id && $0.profile.id == space.profile.id }
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
    func load(_ space: BrowserSpace) async {
        guard authorized(space), let host = CrestChromiumRoot.engineHost else { return }
        let ready = await withCheckedContinuation { continuation in
            host.prepareExtensionProfile(space.profile.id.uuidString) { ready in continuation.resume(returning: ready) }
        }
        guard ready, authorized(space) else { return }
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
    @discardableResult
    func command(_ command: String, extensionID: String = "", space: BrowserSpace, window: NSWindow? = nil) -> Bool {
        guard authorized(space), let host = CrestChromiumRoot.engineHost,
              let window = window ?? CrestChromiumRoot.activeNativeWindow,
              let windowID = window.identifier?.rawValue else { return false }
        let destination: String?
        switch command {
        case "store": destination = "https://chromewebstore.google.com/"
        case "manage": destination = "chrome://extensions/"
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
    func presentMenu(_ action: BrowserExtensionActionPresentation, space: BrowserSpace, anchor: BrowserExtensionPopupAnchor?) {
        let menu = NSMenu()
        let handler = ExtensionMenuHandler { [weak self] in self?.togglePin(action, space: space) }
        let item = NSMenuItem(title: action.isPinned ? "Unpin from Toolbar" : "Pin to Toolbar", action: #selector(ExtensionMenuHandler.invoke), keyEquivalent: "")
        item.target = handler
        menu.addItem(item)
        if let source = anchor?.presentationSource(fallbackWindow: CrestChromiumRoot.activeNativeWindow) {
            menu.popUp(positioning: nil, at: NSPoint(x: source.rect.minX, y: source.rect.minY), in: source.view)
        } else { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
        withExtendedLifetime(handler) {}
    }
    func install(_ id: String, in space: BrowserSpace, anchor: NSView?, copies: Set<SpaceID> = []) {
        guard installation == nil, authorized(space), let window = anchor?.window ?? CrestChromiumRoot.activeNativeWindow else { return }
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
        popover.show(relativeTo: NSRect(x: min(160, source.bounds.midX), y: source.bounds.maxY - 44, width: 1, height: 1), of: source, preferredEdge: .minY)
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
    }
}

@MainActor private final class ExtensionMenuHandler: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
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
    var isAuthorized: Bool { store.authorized(space) && (targetSpace.map(store.authorized) ?? true) }
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
