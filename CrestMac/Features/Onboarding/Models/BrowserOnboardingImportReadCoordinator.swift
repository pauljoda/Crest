import Foundation
import Observation

struct BrowserOnboardingImportReadOutput: Sendable {
    let payload: BrowserDetectedImportPayload
    /// The Spaces the core read, with new identities.
    let imported: [SpaceState]
    let passwordCandidates: [BrowserPasswordImportCandidate]
    /// The extensions each Space offers to install, for the browsers that
    /// keep them where Crest reads them.
    var extensions: [ImportSpaceExtensions] = []
    /// The icon each offered extension wears, by its identifier.
    var extensionIcons: [String: Data] = [:]
    /// What the browser held that the import cannot bring, and why.
    var leftOut: [ImportLeftOut] = []
}

@Observable
@MainActor
final class BrowserOnboardingImportReadCoordinator {

    /// The read under way, if any.
    private var readingID: UUID?

    var isInFlight: Bool {
        readingID != nil
    }

    @ObservationIgnored private let reader: any BrowserOnboardingImportReading
    @ObservationIgnored private var readTask: Task<Void, Never>?

    init(reader: any BrowserOnboardingImportReading) {
        self.reader = reader
    }

    func startReading(
        _ payload: BrowserDetectedImportPayload,
        onFinish: @escaping @MainActor () -> Void = {},
        completion:
            @escaping @MainActor (
                Result<BrowserOnboardingImportReadOutput, any Error>
            ) -> Void
    ) {
        cancel()

        let requestID = UUID()
        let reader = self.reader
        readingID = requestID
        readTask = Task { @MainActor [weak self] in
            defer { onFinish() }

            let result: Result<BrowserOnboardingImportReadOutput, any Error>
            do {
                try Task.checkCancellation()
                let output = try await reader.read(payload)
                try Task.checkCancellation()
                result = .success(output)
            } catch is CancellationError {
                self?.finish(requestID: requestID)
                return
            } catch {
                result = .failure(error)
            }

            guard self?.finish(requestID: requestID) == true else { return }
            completion(result)
        }
    }

    func cancel() {
        readTask?.cancel()
        readTask = nil
        readingID = nil
    }

    @discardableResult
    private func finish(requestID: UUID) -> Bool {
        guard readingID == requestID else { return false }
        readTask = nil
        readingID = nil
        return true
    }
}
