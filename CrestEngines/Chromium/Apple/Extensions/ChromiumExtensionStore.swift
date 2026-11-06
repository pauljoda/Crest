import AppKit
import Observation
import SwiftUI

// MARK: - Types

/// How many times one Space's extensions changed, observed apart from every
/// other Space's so a badge change redraws only that Space's rows.
@Observable @MainActor
private final class ProfileExtensionRevision {
    var value = 0
}

/// Native presentation of the extensions Chromium keeps for the person's
/// Spaces: the toolbar's actions and icons, which the engine answers directly,
/// and the menus, confirmations and install review. Which Spaces may change,
/// where a copy may go and which consent answers a later question are the
/// core's: every change and install is an intent the core checks first, and
/// what each Space has comes from the core's read model.
@Observable @MainActor
final class ChromiumExtensionStore {
    // MARK: - Static Variables

    /// The shortest time between two refreshes of one Space's extensions. A
    /// blocker's count changes many times while a page loads, and each refresh
    /// redraws the Space's rows on the main thread that also carries the
    /// page's scroll input.
    private static let refreshInterval = Duration.milliseconds(250)

    // MARK: - Types

    struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String
        let detail: String
        let icon: NSImage?
        let enabled: Bool
        /// The person may enable, disable, pin or remove it; one a policy
        /// manages they may not, and the core refuses each change.
        let changeable: Bool
        let permissions: [String]
        let webStore: Bool
        let options: String
        init(_ item: InstalledExtension, icon: NSImage?) {
            id = item.id
            name = item.name.isEmpty ? item.id : item.name
            version = item.version
            detail = item.description
            self.icon = icon
            enabled = item.enabled
            changeable = item.changeable
            permissions = item.permissions
            webStore = item.fromWebStore
            options = item.optionsURL ?? ""
        }
    }

    // MARK: - Variables

    /// Advances for a change that reaches every Space's rows.
    var revision = 0
    @ObservationIgnored private var profileRevisions: [UUID: ProfileExtensionRevision] = [:]
    /// Spaces whose extensions changed while a refresh was too recent,
    /// refreshed together when the interval ends.
    @ObservationIgnored private var pendingRefreshes: Set<UUID> = []
    @ObservationIgnored private var refreshWindow: Task<Void, Never>?
    private(set) var installation: ChromiumExtensionInstallation?
    /// Each profile's extension icons, as the engine last answered them.
    @ObservationIgnored private var icons: [UUID: [String: NSImage]] = [:]
    /// The extensions an import brought that still wait to install.
    @ObservationIgnored private var pendingImports: [ImportExtensionInstall] = []
    @ObservationIgnored private var importsTask: Task<Void, Never>?
    @ObservationIgnored private var popover: NSPopover?
    @ObservationIgnored private var windowClosed: NSObjectProtocol?
    /// The one-point view the install review is anchored to. It belongs to the
    /// window's own hosting view and is removed with the review.
    @ObservationIgnored private var anchorSpot: NSView?
    /// Runs when the presented install operation ends, however it ended. The
    /// Chrome Web Store listing that started it uses this to restate its own
    /// button instead of leaving it in the progress label.
    @ObservationIgnored private var installCompletion: (@MainActor () -> Void)?

    /// The person's own Spaces, which the extension views name.
    var spaces: [BrowserSpaceIdentity] { ChromiumComposition.personSpaces.map(\.identity) }
    private var core: CrestCore? { ChromiumComposition.core }

    // MARK: - Actions - Spaces

    /// The person's own Space `id` names.
    func space(_ id: UUID) -> BrowserSpaceIdentity? {
        ChromiumComposition.personSpaces.first { $0.id == id }?.identity
    }

    /// Whether another Space browses with `space`'s profile, as a group's
    /// Spaces do, so an extension removed from one leaves them all.
    func sharesProfile(_ space: BrowserSpaceIdentity) -> Bool {
        spaces.contains { $0.id != space.id && $0.profileID == space.profileID }
    }

    /// Whether the core lets `space`'s extensions change now; a private
    /// window's, a locked Space's and one being deleted do not.
    func mayChange(_ space: BrowserSpaceIdentity) -> Bool {
        guard let permission = try? core?.query(CanChangeExtensions(spaceID: space.id, engine: .chromium)) else {
            return false
        }
        return permission.refusal == nil
    }

    // MARK: - Actions - Listing

    /// The extensions the core lists for `space`'s profile, with their icons,
    /// or nil before the engine listed it.
    func installed(in space: BrowserSpaceIdentity) -> [Installed]? {
        observeChanges(of: space.profileID)
        guard let listed = core?.state.installedExtensions[.chromium]?[space.profileID] else { return nil }
        return listed.map { Installed($0, icon: icon($0.id, in: space.profileID)) }
    }

    /// Asks the core to list `space`'s extensions, which the engine loads the
    /// Space's profile for. A Space the core refuses lists nothing.
    func load(_ space: BrowserSpaceIdentity) {
        send(ListExtensions(spaceID: space.id, engine: .chromium), reportsRefusal: false)
    }

    /// Makes sure the Space's engine profile is listed, so its pinned row
    /// shows before anything has been opened in it. Idempotent: a Space the
    /// core already lists is left as it is, so the row can ask on every
    /// appearance and every Space change.
    func prepare(_ space: BrowserSpaceIdentity) {
        guard core?.state.installedExtensions[.chromium]?[space.profileID] == nil else { return }
        load(space)
    }

    /// The engine changed something the toolbar or the extension list shows.
    func refresh() {
        revision &+= 1
        icons = [:]
    }
    /// The engine changed something `profileID`'s Space shows. Refreshes only
    /// that Space, at once when it was last refreshed longer ago than
    /// `refreshInterval`, and otherwise together with every other change that
    /// arrives before the interval ends. Badge and icon updates arrive per
    /// profile while pages load, and each refresh asks the engine for that
    /// Space's actions and their icons again.
    func refresh(profile profileID: UUID) {
        pendingRefreshes.insert(profileID)
        guard refreshWindow == nil else { return }
        refreshPending()
    }
    private func refreshPending() {
        let due = pendingRefreshes
        pendingRefreshes.removeAll()
        guard !due.isEmpty else {
            refreshWindow = nil
            return
        }
        // A profile's revision stays even once no Space of the person's uses
        // it: a private window's profile is never one, and its rows keep
        // observing the revision they read.
        let profiles = Set(spaces.map { $0.profileID })
        if icons.keys.contains(where: { !profiles.contains($0) }) {
            icons = icons.filter { profiles.contains($0.key) }
        }
        for profileID in due {
            icons[profileID] = nil
            profileRevision(profileID).value &+= 1
        }
        refreshWindow = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshInterval)
            self?.refreshPending()
        }
    }
    private func profileRevision(_ profileID: UUID) -> ProfileExtensionRevision {
        if let revision = profileRevisions[profileID] { return revision }
        let revision = ProfileExtensionRevision()
        profileRevisions[profileID] = revision
        return revision
    }
    /// Makes the calling view follow changes that reach every Space and those
    /// of `profileID`'s Space alone.
    private func observeChanges(of profileID: UUID?) {
        _ = revision
        if let profileID { _ = profileRevision(profileID).value }
    }

    private func icon(_ extensionID: String, in profileID: UUID) -> NSImage? {
        if icons[profileID] == nil, ChromiumComposition.engineHost != nil,
            let pages = ChromiumComposition.chromiumEngine?.pages
        {
            icons[profileID] = Dictionary(
                pages.request(ExtensionIcons(profileID: profileID)).icons.compactMap { icon in
                    icon.image.flatMap(NSImage.extensionIcon).map { (icon.extensionID, $0) }
                },
                uniquingKeysWith: { first, _ in first })
        }
        return icons[profileID]?[extensionID]
    }

    // MARK: - Actions - Toolbar

    func actions(for page: ChromiumNativePage) -> [BrowserExtensionActionPresentation] {
        observeChanges(of: page.profileID)
        return page.extensions
    }
    /// The pinned actions of a Space's own toolbar row.
    ///
    /// The row belongs to the Space, so the pinned list comes from the Space's
    /// profile and is present whether or not a page is open. Where a page is
    /// open its per-tab state — badge, dynamic icon, whether a page action has
    /// anything to act on — is overlaid on top of it.
    func pinnedActions(
        for space: BrowserSpaceIdentity, page: ChromiumNativePage?
    ) -> [BrowserExtensionActionPresentation] {
        observeChanges(of: space.profileID)
        guard ChromiumComposition.engineHost != nil, let pages = ChromiumComposition.chromiumEngine?.pages else {
            return []
        }
        let live = Dictionary(
            page?.extensions.map { ($0.id, $0) } ?? [],
            uniquingKeysWith: { first, _ in first })
        return pages.request(PinnedExtensions(profileID: space.profileID)).actions
            .map { action -> BrowserExtensionActionPresentation in
                if let tab = live[action.id] {
                    return BrowserExtensionActionPresentation(
                        id: tab.id, displayName: tab.displayName,
                        badgeText: tab.badgeText, icon: tab.icon, isPinned: true)
                }
                return BrowserExtensionActionPresentation(action)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    /// Runs a pinned action from a Space with no page open. Only an action with
    /// its own popup can run without one, so anything else states itself as
    /// unavailable rather than doing nothing.
    func runPinned(
        _ action: BrowserExtensionActionPresentation, space: BrowserSpaceIdentity,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        let fallback = ChromiumComposition.activeNativeWindow
        let anchor =
            anchor
            ?? BrowserExtensionPopupAnchor(
                screenPoint: NSEvent.mouseLocation,
                sourceWindow: fallback)
        guard let host = ChromiumComposition.engineHost,
            let source = anchor.presentationSource(fallbackWindow: fallback),
            let windowID = source.view.window?.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
            host.runExtension(
                action.id, profile: space.profileID, window: windowID,
                anchorView: source.view, anchorRect: source.rect)
        else {
            ChromiumComposition.showNativeNotice(
                String(localized: "This extension action needs an open page."),
                icon: "puzzlepiece.extension")
            return
        }
    }

    // MARK: - Actions - Commands

    /// Runs `command` for the extension `extensionID` names in `space`: opens
    /// the page it names in `window`, or asks the core to make its change,
    /// which says why when it refuses. False when the core refused the change,
    /// or when the command has nothing to open and no change to make.
    @discardableResult
    func command(
        _ command: ExtensionCommand, extensionID: String = "", space: BrowserSpaceIdentity, window: NSWindow? = nil
    ) -> Bool {
        let options = installed(in: space)?.first { $0.id == extensionID }?.options
        if let destination = command.destination(extensionID, options), let url = URL(string: destination) {
            guard let window = window ?? ChromiumComposition.activeNativeWindow else { return false }
            return ChromiumComposition.openExtensionURL(url, in: space, window: window)
        }
        guard let change = command.change else { return false }
        return send(ChangeExtension(spaceID: space.id, engine: .chromium, extensionID: extensionID, change: change))
    }
    func togglePin(_ action: BrowserExtensionActionPresentation, space: BrowserSpaceIdentity) {
        command(action.isPinned ? .unpin : .pin, extensionID: action.id, space: space)
    }
    /// The installed record backing an action, so the menu offers only the
    /// verbs the extension supports.
    private func installedRecord(_ extensionID: String, in space: BrowserSpaceIdentity) -> Installed? {
        installed(in: space)?.first { $0.id == extensionID }
    }

    /// Sends `intent` to the core. When the core refuses it, the person reads
    /// why in a notice, unless `reportsRefusal` is false.
    @discardableResult
    private func send(_ intent: some Intent, reportsRefusal: Bool = true) -> Bool {
        guard let core else { return false }
        do {
            try core.send(intent)
            return true
        } catch {
            if reportsRefusal { reportRefusal(error) }
            return false
        }
    }

    private func reportRefusal(_ rejection: Rejection) {
        BrowserNoticeCenter.shared.post(
            BrowserNotice(
                message: rejection.message.map { String(localized: $0) }
                    ?? String(
                        localized:
                            "Couldn’t complete that extension action. Check its details for policy or permission requirements."
                    ),
                systemImage: "exclamationmark.triangle"))
    }

    // MARK: - Actions - Menus

    /// - Parameter openSidePanel: Supplied only when the extension has a side
    ///   panel entry for the page the action was presented on. The caller owns
    ///   the window the panel would mount into, so it also owns the check.
    /// - Parameter closeSource: Closes the surface the menu opened over, such
    ///   as Site Controls, before an item that leads somewhere else runs. The
    ///   surface stays open while the menu shows and when it is dismissed.
    func presentMenu(
        _ action: BrowserExtensionActionPresentation, space: BrowserSpaceIdentity,
        anchor: BrowserExtensionPopupAnchor?,
        openSidePanel: (@MainActor () -> Void)? = nil,
        closeSource: (() -> Void)? = nil
    ) {
        let menu = NSMenu(title: action.displayName)
        menu.autoenablesItems = false
        let handler = ExtensionMenuHandler(closeSource: closeSource)
        let record = installedRecord(action.id, in: space)
        // The core decides whether the Space's extensions may change: a
        // private window's never do, so only the navigation verbs are offered
        // from one. An extension a policy manages offers no change either.
        let spaceChanges = mayChange(space)
        let opensSettings = spaceChanges && (record.map { !$0.options.isEmpty && $0.enabled } ?? true)
        let changeable = spaceChanges && (record?.changeable ?? true)
        if let openSidePanel {
            menu.addItem(handler.item(String(localized: "Open Side Panel")) { openSidePanel() })
            menu.addItem(.separator())
        }
        if opensSettings {
            menu.addItem(
                handler.item(String(localized: "Extension Settings…")) { [weak self] in
                    self?.command(.options, extensionID: action.id, space: space)
                })
        }
        if changeable {
            menu.addItem(
                handler.item(
                    action.isPinned
                        ? String(localized: "Unpin from Toolbar") : String(localized: "Pin to Toolbar"),
                    keepsSource: true
                ) { [weak self] in
                    self?.togglePin(action, space: space)
                })
            if let record {
                menu.addItem(
                    handler.item(
                        record.enabled
                            ? String(localized: "Disable Extension") : String(localized: "Enable Extension")
                    ) { [weak self] in
                        self?.command(record.enabled ? .disable : .enable, extensionID: action.id, space: space)
                    })
            }
        }
        if opensSettings || changeable { menu.addItem(.separator()) }
        menu.addItem(
            handler.item(String(localized: "Manage Extension…")) { [weak self] in
                self?.command(.details, extensionID: action.id, space: space)
            })
        menu.addItem(
            handler.item(String(localized: "Manage Extensions…")) { [weak self] in
                self?.command(.manage, space: space)
            })
        if record?.webStore ?? false {
            menu.addItem(
                handler.item(String(localized: "View on Chrome Web Store")) { [weak self] in
                    self?.command(.store, extensionID: action.id, space: space)
                })
        }
        if changeable, let record {
            menu.addItem(.separator())
            menu.addItem(
                handler.item(String(localized: "Remove Extension…")) { [weak self] in
                    self?.confirmRemoval(record, space: space)
                })
        }
        if let source = anchor?.presentationSource(fallbackWindow: ChromiumComposition.activeNativeWindow) {
            menu.popUp(positioning: nil, at: NSPoint(x: source.rect.minX, y: source.rect.minY), in: source.view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        withExtendedLifetime(handler) {}
    }
    /// Removal asked for by identifier — the Chrome Web Store listing for an
    /// extension already installed in this Space. The confirmation and the
    /// core's intent are the menu's own.
    func confirmRemoval(
        _ extensionID: String, in space: BrowserSpaceIdentity,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard let record = installedRecord(extensionID, in: space) else {
            completion?()
            return
        }
        confirmRemoval(record, space: space, completion: completion)
    }
    /// Mirrors the confirmation the extension settings pane requires before an
    /// uninstall. The menu's tracking loop owns the event while an item runs, so
    /// the alert is presented once the menu has dismissed.
    private func confirmRemoval(
        _ record: Installed, space: BrowserSpaceIdentity,
        completion: (@MainActor () -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.mayChange(space) else {
                completion?()
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Remove \(record.name)?")
            alert.informativeText =
                sharesProfile(space)
                ? String(localized: "\(record.name) and its data will be removed from every Space in this group.")
                : String(
                    localized:
                        "\(record.name) and its Space-local data will be removed. Other Spaces are unchanged.")
            alert.addButton(withTitle: String(localized: "Remove from \(space.name)"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.buttons.first?.hasDestructiveAction = true
            let complete: (NSApplication.ModalResponse) -> Void = { response in
                MainActor.assumeIsolated {
                    defer { completion?() }
                    guard response == .alertFirstButtonReturn else { return }
                    self.command(.remove, extensionID: record.id, space: space)
                }
            }
            if let window = ChromiumComposition.activeNativeWindow {
                alert.beginSheetModal(for: window, completionHandler: complete)
            } else {
                complete(alert.runModal())
            }
        }
    }

    // MARK: - Actions - Copies

    /// The Spaces a copy of `extensionID` from `space` may go to, as the core
    /// answers it from what each Space's profile has.
    func destinations(for extensionID: String, from space: BrowserSpaceIdentity) -> [BrowserSpaceIdentity] {
        // Reading the lists the core published redraws a view that shows the
        // answer once another profile's arrives.
        _ = core?.state.installedExtensions[.chromium]
        guard
            let answer = try? core?.query(
                ExtensionCopyDestinations(spaceID: space.id, engine: .chromium, extensionID: extensionID))
        else { return [] }
        return answer.spaceIDs.compactMap(self.space)
    }

    /// Whether the core has heard from every profile a copy of `extensionID`
    /// from `space` could go to.
    func destinationsListed(for extensionID: String, from space: BrowserSpaceIdentity) -> Bool {
        _ = core?.state.installedExtensions[.chromium]
        let answer = try? core?.query(
            ExtensionCopyDestinations(spaceID: space.id, engine: .chromium, extensionID: extensionID))
        return answer?.listed ?? false
    }

    // MARK: - Actions - Imports

    /// Says what an import's extensions came to: those installed, and those
    /// that could not be.
    private func reportImportedInstalls(added: [String], failed: [String]) {
        if !added.isEmpty {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(
                    message: added.count == 1
                        ? String(localized: "Installed \(added[0])")
                        : String(localized: "Installed \(added.count) extensions"),
                    systemImage: "puzzlepiece.extension.fill"))
        }
        if !failed.isEmpty {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(
                    message: String(localized: "Couldn’t install \(failed.formatted(.list(type: .and)))"),
                    systemImage: "exclamationmark.triangle"))
        }
    }
    /// Installs the extensions an import brought, one at a time and without
    /// asking again: the person chose each when they reviewed the import, and
    /// the core accepts the engine's question for them. It waits for the
    /// Spaces the import made to appear, and says once, when the queue
    /// empties, what it installed and what it could not. The core decides
    /// which of the Spaces each goes to.
    func installImported(_ installs: [ImportExtensionInstall]) {
        pendingImports += installs
        guard importsTask == nil else { return }
        importsTask = Task { [weak self] in
            await self?.runPendingImports()
            self?.importsTask = nil
        }
    }
    private func runPendingImports() async {
        var added: [String] = []
        var failed: [String] = []
        defer { reportImportedInstalls(added: added, failed: failed) }
        while !pendingImports.isEmpty, !Task.isCancelled {
            let next = pendingImports.removeFirst()
            guard let ended = await installImport(next) else {
                failed.append(next.name)
                continue
            }
            if !ended.stage.hasInstalled {
                failed.append(next.name)
            } else if ended.installedCount > 0 {
                added.append(next.name)
            }
        }
    }
    /// Installs one extension an import brought in the Spaces it chose, from
    /// the first of them the core accepts, and answers how the install ended,
    /// or nil when no Space took it.
    private func installImport(_ install: ImportExtensionInstall) async -> ExtensionInstallState? {
        var spaceIDs = await importedSpaces(install.spaceIDs)
        while let first = spaceIDs.first, !Task.isCancelled {
            let installID = UUID()
            if send(
                InstallExtension(
                    installID: installID, spaceID: first, engine: .chromium, extensionID: install.extensionID,
                    copySpaceIDs: Array(spaceIDs.dropFirst()), preApproved: true),
                reportsRefusal: false)
            {
                return await ending(of: installID)
            }
            spaceIDs.removeFirst()
        }
        return nil
    }
    /// The Spaces of `spaceIDs` that exist, once each import made them. It
    /// waits however long setup holds them back, and gives up only on a Space
    /// that never appears.
    private func importedSpaces(_ spaceIDs: [UUID]) async -> [UUID] {
        var missing = 0
        while !Task.isCancelled, spaceIDs.contains(where: { space($0) == nil }), missing < 60 {
            missing += 1
            try? await Task.sleep(for: .milliseconds(500))
        }
        return spaceIDs.filter { space($0) != nil }
    }
    /// How the install `installID` ended, once it did.
    private func ending(of installID: UUID) async -> ExtensionInstallState? {
        while !Task.isCancelled {
            if let state = core?.state.extensionInstalls[installID], state.stage.hasEnded { return state }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    // MARK: - Actions - Installs

    func install(
        _ id: String, in space: BrowserSpaceIdentity, anchor: NSView?, copies: Set<UUID> = [],
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard installation == nil, let window = anchor?.window ?? ChromiumComposition.activeNativeWindow else {
            completion?()
            return
        }
        let job = ChromiumExtensionInstallation(extensionID: id, space: space, window: window, store: self)
        job.selectedSpaces = copies
        guard
            send(
                InstallExtension(
                    installID: job.id, spaceID: space.id, engine: .chromium, extensionID: id, copySpaceIDs: [],
                    preApproved: false))
        else {
            completion?()
            return
        }
        installCompletion = completion
        installation = job
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: BrowserChromeWebStoreInstallView(model: job))
        self.popover = popover
        // Anchor native presentation in Crest's hosting view. Anchoring it in
        // Chromium's responder subtree lets web focus consume popover input.
        guard let source = window.contentView else {
            dismissInstallation()
            return
        }
        // AppKit reads a caller's positioning rectangle as if the view were not
        // flipped, and SwiftUI's hosting view is flipped: a rectangle measured
        // from its top edge presented the review past the window's lower edge
        // and off the screen. A one-point positioning view carries the anchor
        // instead, because a subview's own frame is resolved in its superview's
        // coordinate space whichever way that space runs.
        let spot = NSView(
            frame: NSRect(
                x: min(160, source.bounds.width / 2),
                y: source.isFlipped ? 44 : source.bounds.height - 44, width: 1, height: 1))
        source.addSubview(spot)
        anchorSpot = spot
        popover.show(relativeTo: .zero, of: spot, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        windowClosed = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissInstallation() }
        }
    }
    /// The core asks the person whether to install the package an install
    /// verified. The review showing that install shows the question; one no
    /// review shows any more is declined.
    func review(_ asked: ExtensionInstallAsked) {
        guard let job = installation, job.id == asked.installID else {
            send(
                AnswerExtensionInstall(
                    promptID: asked.promptID, accepted: false, withholdsSiteAccess: false, copySpaceIDs: []),
                reportsRefusal: false)
            return
        }
        job.review(asked)
    }
    /// Sends the person's answer to an install's question.
    fileprivate func answer(_ answer: AnswerExtensionInstall) {
        send(answer)
    }
    /// Stops the install `installID` names.
    fileprivate func cancel(_ installID: UUID) {
        send(CancelExtensionInstall(installID: installID), reportsRefusal: false)
    }
    /// The download of install `installID` received `fraction` of its package.
    func downloadProgressed(_ installID: UUID, fraction: Double) {
        guard let installation, installation.id == installID else { return }
        installation.downloaded = fraction
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

extension ChromiumExtensionStore: BrowserImportedExtensionInstalling {}

/// Owns the menu item closures; `NSMenuItem.target` is weak, so this has to
/// outlive the menu's tracking loop.
@MainActor private final class ExtensionMenuHandler: NSObject {
    private let closeSource: (() -> Void)?
    private var handlers: [() -> Void] = []

    init(closeSource: (() -> Void)?) {
        self.closeSource = closeSource
    }

    /// - Parameter keepsSource: The item changes something the source surface
    ///   shows, so the surface stays open after it runs.
    func item(_ title: String, keepsSource: Bool = false, perform: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        item.tag = handlers.count
        if keepsSource || closeSource == nil {
            handlers.append(perform)
        } else {
            handlers.append { [closeSource] in
                closeSource?()
                Task { @MainActor in
                    await Task.yield()
                    perform()
                }
            }
        }
        return item
    }
    @objc private func invoke(_ sender: NSMenuItem) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}

/// The install review's model: what the person sees of one install the core
/// runs, the question it asks, and the person's choices before they answer.
@Observable @MainActor
final class ChromiumExtensionInstallation {
    // MARK: - Variables

    /// The core's identity for the install.
    let id = UUID()
    let extensionID: String
    let space: BrowserSpaceIdentity
    weak var window: NSWindow?
    private let store: ChromiumExtensionStore
    /// The verified package the core asks the person about, as its question
    /// presents it.
    private(set) var question: ExtensionInstallQuestion?
    /// The name the review shows: the package's own, or its identifier when
    /// it names none.
    var questionName: String? { question.map { $0.name.isEmpty ? $0.extensionID : $0.name } }
    var questionIcon: NSImage? { question?.icon.flatMap(NSImage.init(data:)) }
    var selectedSpaces: Set<UUID> = []
    var withhold = false
    private(set) var canWithhold = false
    /// The fraction of the package received, once its download knows its size.
    var downloaded: Double?
    private(set) var canAccept = false
    /// The question waiting on the person's answer, until they give it.
    @ObservationIgnored private var promptID: UUID?

    /// The install as the core last published it.
    private var state: ExtensionInstallState? { ChromiumComposition.core?.state.extensionInstalls[id] }
    var preparing: Bool { state?.stage.isPreparing ?? true }
    var installing: Bool { state?.stage.isInstalling ?? false }
    var completed: Bool { state?.stage.hasInstalled ?? false }
    var installedCount: Int { state?.installedCount ?? 0 }
    var failure: String? { state?.failure.map { String(localized: $0.message) } }
    /// The install ended because its Space went out of reach, so the review
    /// closes.
    var closesReview: Bool { state?.failure?.closesReview == true }
    /// The Spaces a copy may go to, as the core answers it.
    var destinations: [BrowserSpaceIdentity] { store.destinations(for: extensionID, from: space) }

    // MARK: - Initializers

    init(extensionID: String, space: BrowserSpaceIdentity, window: NSWindow, store: ChromiumExtensionStore) {
        self.extensionID = extensionID
        self.space = space
        self.window = window
        self.store = store
    }

    // MARK: - Actions - Review

    /// The core asks the person whether to install the package the engine
    /// verified. Accepting waits a moment, so a click meant for something
    /// else does not land on it.
    func review(_ asked: ExtensionInstallAsked) {
        promptID = asked.promptID
        question = asked.question
        canWithhold = asked.question.canWithholdSiteAccess
        withhold = asked.question.withholdsSiteAccess
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.canAccept = true
        }
    }
    func accept() {
        guard canAccept, let promptID else { return }
        self.promptID = nil
        let copies = destinations.filter { selectedSpaces.contains($0.id) }.map(\.id)
        store.answer(
            AnswerExtensionInstall(
                promptID: promptID, accepted: true, withholdsSiteAccess: withhold, copySpaceIDs: copies))
    }
    func cancel() {
        promptID = nil
        store.cancel(id)
    }
    func dismiss() { store.dismissInstallation() }
}
