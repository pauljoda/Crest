import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MobileLinkPeekPressCoordinator {

    private let previewDelay: Duration
    private let minimumDuration: Duration
    private var pendingPresentation: Task<Void, Never>?
    private var activePressID: String?
    private var activeRequestID: UUID?
    private var cancelStagedPresentation: ((UUID) -> Void)?
    private(set) var phase: MobileLinkPeekPressPhase = .idle

    var hasCommittedPress: Bool { phase == .committed }

    init(
        previewDelay: Duration = .milliseconds(90),
        minimumDuration: Duration = .milliseconds(300)
    ) {
        precondition(previewDelay >= .zero)
        precondition(minimumDuration >= previewDelay)
        self.previewDelay = previewDelay
        self.minimumDuration = minimumDuration
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

        pendingPresentation = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: previewDelay)
            } catch {
                return
            }
            guard let self, activePressID == pressID else { return }
            phase = .staged
            stage(request)

            do {
                try await Task.sleep(for: minimumDuration - previewDelay)
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
