import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@Observable
@MainActor
final class MobileDownloadRiskConfirmationCoordinator {
    private struct PendingRequest {
        let request: MobileDownloadRiskConfirmationRequest
        let continuation: CheckedContinuation<Bool, Never>
    }

    private(set) var request: MobileDownloadRiskConfirmationRequest?

    @ObservationIgnored private var current: PendingRequest?
    @ObservationIgnored private var queued: [PendingRequest] = []

    var isPresented: Bool {
        get { request != nil }
        set {
            guard !newValue, let dismissedRequestID = request?.id else { return }
            Task { @MainActor [weak self] in
                await Task.yield()
                guard self?.request?.id == dismissedRequestID else { return }
                self?.cancel()
            }
        }
    }

    func requestApproval(
        assessment: BrowserDownloadRiskAssessment,
        sourceURL: URL?,
        spaceName: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let pending = PendingRequest(
                request: MobileDownloadRiskConfirmationRequest(
                    assessment: assessment,
                    sourceURL: sourceURL,
                    spaceName: spaceName
                ),
                continuation: continuation
            )
            if current == nil {
                present(pending)
            } else {
                queued.append(pending)
            }
        }
    }

    func approve() {
        resolveCurrent(with: true)
    }

    func cancel() {
        resolveCurrent(with: false)
    }

    func cancelAll() {
        let activeContinuation = current?.continuation
        let queuedContinuations = queued.map(\.continuation)
        current = nil
        queued.removeAll()
        request = nil
        activeContinuation?.resume(returning: false)
        for continuation in queuedContinuations {
            continuation.resume(returning: false)
        }
    }

    private func present(_ pending: PendingRequest) {
        current = pending
        request = pending.request
    }

    private func resolveCurrent(with approval: Bool) {
        guard let current else { return }
        self.current = nil
        request = nil
        current.continuation.resume(returning: approval)
        presentNextWhenTheCurrentAlertHasDismissed()
    }

    private func presentNextWhenTheCurrentAlertHasDismissed() {
        guard !queued.isEmpty else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.current == nil, !self.queued.isEmpty else { return }
            self.present(self.queued.removeFirst())
        }
    }
}
