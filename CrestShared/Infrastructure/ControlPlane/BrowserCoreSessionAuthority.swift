import Foundation
import Observation

/// One workspace the core opened for a store family, and the Swift copy of
/// its session. `projection` is that copy, with native favicon assets; only
/// the session changes the core publishes update it (see
/// `BrowserCoreSessionBridge.swift`), so it can never show an unaccepted edit.
/// It holds browsing data only. What each window shows is the core device's:
/// an intent names the window that issued it, and the device moves that
/// window when the intent commits and repairs the others. Nothing here names
/// a revision.
///
/// The core opens the workspace (`OpenWorkspace`, `BorrowSpace`), gives it its
/// identity and closes it (`CloseWorkspace`). Whoever owns the family closes
/// it when its windows go; a workspace no one closed closes once this copy is
/// gone.
@Observable @MainActor
final class BrowserCoreSessionAuthority {
    // MARK: - Types

    /// The images the issuer of a command holds, which `FaviconAssets` places
    /// while the core's changes for the command are applied.
    typealias OfferedImages = FaviconAssets.Offer

    // MARK: - Variables

    private(set) var projection: BrowserSession
    /// Whether the core still holds the workspace open. It closes when this
    /// copy closes it, when the workspace it borrows from closes or stops
    /// lending its Space, and when the core closes it for any other reason.
    private(set) var isOpen = true
    /// The workspace the core gave the session, which every change to it names.
    let workspaceID: UUID
    /// The core whose device shows this session in its windows.
    @ObservationIgnored private(set) weak var device: CrestCore?

    // MARK: - Initializers

    /// The workspace `opened` announced, whose changes reach this copy from
    /// then on. Its tabs wear the images `core` holds for them, so a caller
    /// that brings images of its own adopts them first.
    private init(opened: WorkspaceOpened, core: CrestCore) {
        workspaceID = opened.workspaceID
        device = core
        let images = core.state.favicons
        projection = BrowserSession(core: opened.session, image: { images.image(of: $0) })
        core.state.register(self, for: opened.workspaceID)
    }

    /// A workspace no one closed closes on the main queue's next turn, never
    /// inside this deinit, which may run while the core applies a batch. It
    /// is skipped once the core is gone.
    isolated deinit {
        guard isOpen, let device else { return }
        let closing = CloseWorkspace(workspaceID: workspaceID)
        DispatchQueue.main.async { [weak device] in
            MainActor.assumeIsolated { _ = try? device?.send(closing) }
        }
    }

    // MARK: - Actions - Opening

    /// Opens a workspace of `kind` in `core`. With `seed`, a session in the
    /// stored format for launches without a file (isolated runs, previews,
    /// tests), it keeps nothing: it is never saved or synced, and its tabs wear
    /// the images `seed` carries. Without one, a private workspace starts from
    /// the core's private template. Throws the rule that refuses it.
    static func open(_ kind: WorkspaceKind, seed: BrowserSession?, in core: CrestCore) throws
        -> BrowserCoreSessionAuthority
    {
        let bytes = try seed.map { try JSONEncoder().encode(compact($0)) }
        let opened = Self.opened(by: try core.send(OpenWorkspace(kind: kind, seed: bytes)))
        if let seed { core.state.adoptImages(OfferedImages(placedFrom: seed).placed, in: opened.workspaceID) }
        return BrowserCoreSessionAuthority(opened: opened, core: core)
    }

    /// Opens the session `core` keeps in its file, as it loaded and repaired
    /// it. Each tab wears the image `favicons` keeps for it, and a tab the
    /// repair gave a new identity wears its source's. Throws `NoStoredSession`
    /// while the file holds no session yet.
    static func openStored(in core: CrestCore, favicons: any BrowserFaviconStoring) throws(Rejection)
        -> BrowserCoreSessionAuthority
    {
        let changes = try core.send(OpenWorkspace(kind: .persistent, seed: nil))
        let opened = Self.opened(by: changes)
        var images: [UUID: Data] = [:]
        for space in opened.session.spaces {
            for tab in space.tabs { images[tab.id] = favicons.favicon(tabID: TabID(rawValue: tab.id)) }
        }
        for case .tabCopied(let copied) in changes where copied.workspaceID == opened.workspaceID {
            images[copied.copyTabID] = favicons.favicon(tabID: TabID(rawValue: copied.sourceTabID))
        }
        core.state.adoptImages(images, in: opened.workspaceID)
        return BrowserCoreSessionAuthority(opened: opened, core: core)
    }

    /// Opens a workspace that borrows the Space `assignment` names, with its
    /// profile, settings and access grants, and tabs of its own. It follows
    /// this workspace's edits of the Space's settings and closes once this
    /// workspace no longer lends it. Throws the rule that refuses it.
    func borrow(_ assignment: BrowserSpaceRuntimeAssignment) throws(Rejection) -> BrowserCoreSessionAuthority {
        guard let device else { preconditionFailure("A workspace lends its Space only while its core exists.") }
        let changes = try device.send(
            BorrowSpace(workspaceID: workspaceID, spaceID: assignment.spaceID.rawValue, profileID: assignment.profileID)
        )
        return BrowserCoreSessionAuthority(opened: Self.opened(by: changes), core: device)
    }

    /// The workspace an intent that opens one announced.
    private static func opened(by changes: [Change]) -> WorkspaceOpened {
        for case .workspaceOpened(let opened) in changes.reversed() { return opened }
        preconditionFailure("The core opened a workspace without announcing it. Rebuild the core.")
    }

    // MARK: - Actions - Closing

    /// Closes the workspace, and first every workspace that borrows from it:
    /// its pages and windows go and its session takes no edits. The device
    /// keeps its windows' saved records. Closing it again does nothing.
    func close() {
        guard isOpen else { return }
        _ = try? device?.send(CloseWorkspace(workspaceID: workspaceID))
        isOpen = false
    }

    // MARK: - Actions - Changes

    /// TRANSITIONAL until S6.7: one session change the core published for this
    /// workspace. See `BrowserSession.apply(_:images:)`.
    func receive(_ change: Change, images: FaviconAssets) {
        if case .workspaceClosed = change { isOpen = false }
        projection.apply(change, images: images)
    }

    // MARK: - Actions - Seeds

    private nonisolated static func compactTab(_ source: BrowserTab) -> BrowserTab {
        var tab = source
        tab.faviconData = nil
        return tab
    }

    private nonisolated static func compactArchive(_ source: ArchivedTab) -> ArchivedTab {
        var entry = source
        entry.tab.faviconData = nil
        return entry
    }

    /// `source` without the images its tabs wear, which stay native assets,
    /// as a seed or a sync stage carries it.
    nonisolated static func compact(_ source: BrowserSession) -> BrowserSession {
        var session = source
        for index in session.spaces.indices {
            session.spaces[index].tabs = session.spaces[index].tabs.map(compactTab)
            session.spaces[index].archivedTabs = session.spaces[index].archivedTabs.map(compactArchive)
        }
        return session
    }
}
