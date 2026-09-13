import Foundation
import Observation

@Observable
@MainActor
final class BrowserTransientBrowsingCoordinator {
    private(set) var peekRequest: BrowserPeekRequest?
    private(set) var peekPresentationPhase: BrowserPeekPresentationPhase?
    private(set) var peekMotionState: BrowserPeekMotionState?
    private(set) var quickWindowRequest: BrowserQuickWindowRequest?

    func handleLinkDrag(_ event: BrowserPeekInteractionEvent) {
        switch event {
        case .began(let request, let state): beginPeekDrag(request, state: state)
        case .moved(let id, let state): updatePeekDrag(id: id, state: state)
        case .cancelled(let id): cancelStagedPeek(id: id)
        }
    }

    func presentPeek(_ request: BrowserPeekRequest) {
        beginPeekDrag(request, state: .opening(from: request.sourcePresentation))
        commitPeek(request)
    }

    func stagePeek(_ request: BrowserPeekRequest) {
        peekMotionState = nil
        peekRequest = request
        peekPresentationPhase = .staged
        quickWindowRequest = nil
    }

    func commitPeek(_ request: BrowserPeekRequest) {
        guard
            peekRequest == request,
            peekPresentationPhase == .staged
        else { return }
        peekPresentationPhase = .committed
    }

    func cancelStagedPeek(id: UUID) {
        guard peekRequest?.id == id, peekPresentationPhase == .staged else { return }
        peekRequest = nil
        peekPresentationPhase = nil
        peekMotionState = nil
    }

    func dismissPeek() {
        peekRequest = nil
        peekPresentationPhase = nil
        peekMotionState = nil
    }

    func beginPeekDrag(_ request: BrowserPeekRequest, state: BrowserPeekMotionState) {
        stagePeek(request)
        peekMotionState = state
    }

    func updatePeekDrag(id: UUID, state: BrowserPeekMotionState) {
        guard peekRequest?.id == id, peekPresentationPhase == .staged,
            peekMotionState != nil
        else { return }
        peekMotionState = state
        if state.releasedAt != nil && !state.returnsToSource { peekPresentationPhase = .committed }
    }

    func isPresentingPeek(_ request: BrowserPeekRequest) -> Bool {
        peekRequest == request
    }

    @discardableResult
    func dismissPeek(_ request: BrowserPeekRequest) -> Bool {
        guard isPresentingPeek(request) else { return false }
        dismissPeek()
        return true
    }

    func presentQuickWindow(_ request: BrowserQuickWindowRequest) {
        quickWindowRequest = request
        peekRequest = nil
        peekPresentationPhase = nil
        peekMotionState = nil
    }

    func dismissQuickWindow() {
        quickWindowRequest = nil
    }

    func isPresentingQuickWindow(_ request: BrowserQuickWindowRequest) -> Bool {
        guard let current = quickWindowRequest else { return false }
        return current.hasSamePresentationIdentity(as: request)
    }

    @discardableResult
    func dismissQuickWindow(_ request: BrowserQuickWindowRequest) -> Bool {
        guard isPresentingQuickWindow(request) else { return false }
        dismissQuickWindow()
        return true
    }
}
