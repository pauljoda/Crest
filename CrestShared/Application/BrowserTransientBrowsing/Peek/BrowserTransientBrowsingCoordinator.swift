import Foundation
import Observation

@Observable
@MainActor
final class BrowserTransientBrowsingCoordinator {
    private(set) var peekRequest: BrowserPeekRequest?
    private(set) var peekPresentationPhase: BrowserPeekPresentationPhase?
    private(set) var quickWindowRequest: BrowserQuickWindowRequest?

    func presentPeek(_ request: BrowserPeekRequest) {
        peekRequest = request
        peekPresentationPhase = .committed
        quickWindowRequest = nil
    }

    func stagePeek(_ request: BrowserPeekRequest) {
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
    }

    func dismissPeek() {
        peekRequest = nil
        peekPresentationPhase = nil
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
