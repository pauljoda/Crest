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
/// the Peek starts to grow from the link, and once the press has lasted long
/// enough it opens. A press that ends or moves away first takes the growing
/// Peek back.
@MainActor
final class MobileLinkPeekPressCoordinator {
    /// Waits out one stretch of a press.
    ///
    /// A finger is the clock in production, so this sleeps. A test that has to
    /// release a press after the Peek starts to grow but before it opens
    /// supplies its own instead, so it decides when each stretch ends rather
    /// than racing a timer.
    typealias Wait = @MainActor (Duration) async throws -> Void

    // MARK: - Variables

    private let previewDelay: Duration
    private let minimumDuration: Duration
    private let wait: Wait
    private var pendingPresentation: Task<Void, Never>?
    private var activePressID: String?
    private var activeRequestID: UUID?
    private var cancelStagedPresentation: ((UUID) -> Void)?
    private var settleWaiters: [@MainActor (Bool) -> Void] = []
    private(set) var phase: MobileLinkPeekPressPhase = .idle

    // MARK: - Initializers

    init(
        previewDelay: Duration = .milliseconds(90),
        minimumDuration: Duration = .milliseconds(300),
        wait: @escaping Wait = { try await Task.sleep(for: $0) }
    ) {
        precondition(previewDelay >= .zero)
        precondition(minimumDuration >= previewDelay)
        self.previewDelay = previewDelay
        self.minimumDuration = minimumDuration
        self.wait = wait
    }

    // MARK: - Actions - Presses

    /// Starts the press `pressID` on the link `request` opens: `stage` starts
    /// its Peek growing, `commit` opens it, and `cancelStaged` takes back a
    /// Peek that never opened.
    func begin(
        pressID: String,
        request: BrowserPeekRequest,
        stage: @escaping @MainActor (BrowserPeekRequest) -> Void,
        commit: @escaping @MainActor (BrowserPeekRequest) -> Void,
        cancelStaged: @escaping @MainActor (UUID) -> Void
    ) {
        end()
        activePressID = pressID
        activeRequestID = request.id
        cancelStagedPresentation = cancelStaged
        phase = .pressing
        let previewDelay = self.previewDelay
        let minimumDuration = self.minimumDuration
        let wait = self.wait

        pendingPresentation = Task { @MainActor [weak self] in
            do {
                try await wait(previewDelay)
            } catch {
                return
            }
            guard let self, activePressID == pressID else { return }
            phase = .staged
            stage(request)

            do {
                try await wait(minimumDuration - previewDelay)
            } catch {
                return
            }
            guard activePressID == pressID else { return }
            pendingPresentation = nil
            phase = .committed
            cancelStagedPresentation = nil
            commit(request)
            settle(opensPeek: true)
        }
    }

    /// Ends the press `pressID`, or any press: a Peek that already opened
    /// stays open, and one still growing goes back.
    func end(pressID: String? = nil) {
        guard pressID == nil || pressID == activePressID else { return }
        pendingPresentation?.cancel()
        pendingPresentation = nil
        if phase == .staged, let activeRequestID {
            cancelStagedPresentation?(activeRequestID)
        }
        if phase != .committed {
            settle(opensPeek: false)
        }
        activePressID = nil
        activeRequestID = nil
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
