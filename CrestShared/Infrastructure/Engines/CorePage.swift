import Foundation
import OSLog

/// A page the core opened for this platform. Its identity is made here and
/// never depends on the engine. Giving it a new owner or releasing it goes
/// through the core; a page is released once, and the core then asks its
/// engine to close what it holds.
@MainActor
final class CorePage {
    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Pages")

    let id: UUID
    private weak var core: CrestCore?
    private(set) var isReleased = false

    // MARK: - Initializers

    init(id: UUID = UUID(), core: CrestCore) {
        self.id = id
        self.core = core
    }

    // MARK: - Actions - Ownership

    /// Gives the page to `tabID` in a Space of `workspaceID`, or to a transient
    /// request when `tabID` is nil, hosted by `windowID`. False when a rule
    /// refuses it, such as a window that already hosts a page for the tab or a
    /// Space with another profile.
    func move(to workspaceID: UUID, spaceID: SpaceID, tabID: TabID?, windowID: BrowserWindowID) -> Bool {
        guard !isReleased, let core else { return false }
        do {
            try core.send(
                MovePage(
                    pageID: id, workspaceID: workspaceID, spaceID: spaceID.rawValue, tabID: tabID?.rawValue,
                    windowID: windowID.rawValue))
            return true
        } catch {
            Self.logger.debug(
                "The core kept page \(self.id, privacy: .public) where it was: \(String(describing: error))")
            return false
        }
    }

    /// Tells the core the page is gone. `keepingState` says its owner kept what
    /// it needs to bring the page back. Only the first call counts.
    func release(keepingState: Bool) {
        guard !isReleased else { return }
        isReleased = true
        _ = try? core?.send(ReleasePage(pageID: id, keepsState: keepingState))
        core?.engines.forget(id)
    }

    // MARK: - Actions - Reports

    /// Reports what the page's engine saw it do, through that engine. `icon`
    /// is the image a `PageIconChanged` names. A released page reports nothing.
    func report(_ event: some EngineEvent, icon: Data? = nil) {
        guard !isReleased else { return }
        core?.engines.report(event, for: id, icon: icon)
    }
}
