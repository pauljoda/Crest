import Foundation
import OSLog

/// A page the core opened for this platform. Its identity is made here and
/// never depends on the engine. Giving it a new owner, loading an address in
/// it or releasing it goes through the core; a page is released once, and the
/// core then asks its engine to close what it holds. Its live state is the
/// core's, read from `CoreState`.
@MainActor
final class CorePage {
    // MARK: - Static Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Pages")

    // MARK: - Variables

    let id: UUID
    private weak var core: CrestCore?
    private(set) var isReleased = false
    /// The owner kept what it needs to bring the page back when it released it.
    private var keptState = false
    /// TRANSITIONAL until the WebKit binding builds its own pages: the app's
    /// own load of an address in the platform's page, which WebKit runs when
    /// the core asks it to load one. Set by the page's owner.
    var appLoad: (@MainActor (URL) -> Void)?

    /// The core's model of the page, until the page is gone.
    var state: PageStateModel? { core?.state.pages[id] }

    /// What the page shows now as the core holds it: its engine's latest
    /// report and why its latest navigation failed. Blank until the core
    /// holds the page.
    var live: PageLiveState { state?.live ?? .blank }

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
                    pageID: id, workspaceID: workspaceID, spaceID: spaceID, tabID: tabID,
                    windowID: windowID))
            return true
        } catch {
            Self.logger.debug(
                "The core kept page \(self.id, privacy: .public) where it was: \(String(describing: error))")
            return false
        }
    }

    /// Tells the core the page is gone. `keepingState` says its owner kept what
    /// it needs to bring the page back. A page unloaded that way may be
    /// released again for good, so the core forgets what it showed; any other
    /// call after the first changes nothing.
    func release(keepingState: Bool) {
        guard !isReleased || (keptState && !keepingState) else { return }
        let isFirst = !isReleased
        isReleased = true
        keptState = keepingState
        _ = try? core?.send(ReleasePage(pageID: id, keepsState: keepingState))
        if isFirst { core?.engines.forget(id) }
    }

    // MARK: - Actions - Navigation

    /// Asks the core to load what the person typed or chose, an address or
    /// words to search for, which the core resolves by the rules of the
    /// page's Space and engine. False when a rule refuses it, such as a locked
    /// Space or input that names nothing a page can load.
    @discardableResult
    func navigate(to input: String) -> Bool {
        guard !isReleased, let core else { return false }
        do {
            try core.send(Navigate(pageID: id, input: input))
            return true
        } catch {
            Self.logger.debug(
                "The core loaded nothing in page \(self.id, privacy: .public): \(String(describing: error))")
            return false
        }
    }

    /// Leaves the page's failed navigation for the document behind it.
    func leaveFailure() {
        guard !isReleased, live.failure != nil else { return }
        _ = try? core?.send(LeavePageFailure(pageID: id))
    }

    // MARK: - Actions - Reports

    /// Reports what the page's engine saw it do, through that engine. `icon`
    /// is the image a `PageIconChanged` names. A released page reports nothing.
    func report(_ event: some EngineEvent, icon: Data? = nil) {
        guard !isReleased else { return }
        core?.engines.report(event, for: id, icon: icon)
    }
}
