import Foundation

// MARK: - Types

/// How far a held press on a link has come.
enum MobileLinkPeekPressPhase: Equatable {
    case idle
    case pressing
    case staged
    case committed

    /// Whether a press on a link is under way, or has opened its Peek.
    var holdsLink: Bool { self != .idle }
}

/// Turns a held press on a link into its Peek: shortly after the press begins
/// the Peek starts to grow from the link, and once the page says the press is
/// held, it opens. The page keeps the press's one clock, so a press it holds
/// always opens its Peek and has its ending click swallowed. A press that ends
/// or moves away first takes the growing Peek back.
@MainActor
final class MobileLinkPeekPressCoordinator {
    /// Waits out the stretch before the Peek starts to grow.
    ///
    /// A finger is the clock in production, so this sleeps. A test supplies
    /// its own to decide when the stretch ends rather than racing a timer.
    typealias Wait = @MainActor (Duration) async throws -> Void

    // MARK: - Variables

    private let previewDelay: Duration
    private let wait: Wait
    private var pendingPresentation: Task<Void, Never>?
    private var activePressID: String?
    private var activeRequest: BrowserPeekRequest?
    private var stagePresentation: ((BrowserPeekRequest) -> Void)?
    private var commitPresentation: ((BrowserPeekRequest) -> Void)?
    private var cancelStagedPresentation: ((UUID) -> Void)?
    private var settleWaiters: [@MainActor (Bool) -> Void] = []
    private(set) var phase: MobileLinkPeekPressPhase = .idle

    // MARK: - Initializers

    init(
        previewDelay: Duration = .milliseconds(90),
        wait: @escaping Wait = { try await Task.sleep(for: $0) }
    ) {
        precondition(previewDelay >= .zero)
        self.previewDelay = previewDelay
        self.wait = wait
    }

    // MARK: - Actions - Presses

    /// Starts the press `pressID` on the link `request` opens: `stage` starts
    /// its Peek growing, `commit` opens it once the press is held, and
    /// `cancelStaged` takes back a Peek that never opened.
    func begin(
        pressID: String,
        request: BrowserPeekRequest,
        stage: @escaping @MainActor (BrowserPeekRequest) -> Void,
        commit: @escaping @MainActor (BrowserPeekRequest) -> Void,
        cancelStaged: @escaping @MainActor (UUID) -> Void
    ) {
        end()
        activePressID = pressID
        activeRequest = request
        stagePresentation = stage
        commitPresentation = commit
        cancelStagedPresentation = cancelStaged
        phase = .pressing
        let previewDelay = self.previewDelay
        let wait = self.wait

        pendingPresentation = Task { @MainActor [weak self] in
            do {
                try await wait(previewDelay)
            } catch {
                return
            }
            guard let self, activePressID == pressID, phase == .pressing else { return }
            pendingPresentation = nil
            phase = .staged
            stage(request)
        }
    }

    /// The page held the press `pressID`, which opens its Peek, growing it
    /// first if it hadn't started yet.
    func hold(pressID: String) {
        guard pressID == activePressID, phase.holdsLink, phase != .committed, let request = activeRequest else {
            return
        }
        pendingPresentation?.cancel()
        pendingPresentation = nil
        if phase == .pressing { stagePresentation?(request) }
        phase = .committed
        cancelStagedPresentation = nil
        commitPresentation?(request)
        settle(opensPeek: true)
    }

    /// Ends the press `pressID`, or any press: a Peek that already opened
    /// stays open, and one still growing goes back.
    func end(pressID: String? = nil) {
        guard pressID == nil || pressID == activePressID else { return }
        pendingPresentation?.cancel()
        pendingPresentation = nil
        if phase == .staged, let activeRequest {
            cancelStagedPresentation?(activeRequest.id)
        }
        if phase != .committed {
            settle(opensPeek: false)
        }
        activePressID = nil
        activeRequest = nil
        stagePresentation = nil
        commitPresentation = nil
        cancelStagedPresentation = nil
        phase = .idle
    }

    /// Calls `body` once the press opens its Peek, with true, or ends
    /// without opening it, with false; at once when it already has.
    func whenSettled(_ body: @escaping @MainActor (Bool) -> Void) {
        guard phase.holdsLink else {
            body(false)
            return
        }
        guard phase != .committed else {
            body(true)
            return
        }
        settleWaiters.append(body)
    }

    private func settle(opensPeek: Bool) {
        let waiters = settleWaiters
        settleWaiters = []
        for waiter in waiters { waiter(opensPeek) }
    }
}
