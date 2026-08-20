import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MobileLinkPeekPressCoordinator {

    /// Waits out one stretch of a press.
    ///
    /// A finger is the clock in production, so this sleeps. A test that has to
    /// release a press after the lift but before the commit supplies its own
    /// instead: it decides when each stretch ends rather than racing a timer a
    /// busy machine can run down first.
    typealias Wait = @MainActor (Duration) async throws -> Void

    private let previewDelay: Duration
    private let minimumDuration: Duration
    private let wait: Wait
    private var pendingPresentation: Task<Void, Never>?
    private var activePressID: String?
    private var activeRequestID: UUID?
    private var cancelStagedPresentation: ((UUID) -> Void)?
    private(set) var phase: MobileLinkPeekPressPhase = .idle

    var hasCommittedPress: Bool { phase == .committed }

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

    func begin(
        pressID: String = UUID().uuidString,
        request: BrowserPeekRequest,
        stage: @escaping @MainActor (BrowserPeekRequest) -> Void,
        commit: @escaping @MainActor (BrowserPeekRequest) -> Void,
        cancelStaged: @escaping @MainActor (UUID) -> Void
    ) {
        cancel()
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
        }
    }

    func end(pressID: String? = nil) {
        guard pressID == nil || pressID == activePressID else { return }
        finishActivePress()
    }

    func cancel() {
        finishActivePress(resetsCommittedPhase: true)
    }

    private func finishActivePress(resetsCommittedPhase: Bool = false) {
        pendingPresentation?.cancel()
        pendingPresentation = nil
        if phase == .staged, let activeRequestID {
            cancelStagedPresentation?(activeRequestID)
        }
        activePressID = nil
        activeRequestID = nil
        cancelStagedPresentation = nil
        if phase != .committed || resetsCommittedPhase {
            phase = .idle
        }
    }
}
