import Foundation
import Observation

@Observable
@MainActor
final class BrowserCredentialSuggestionModel {

    private(set) var phase = BrowserCredentialSuggestionPhase.idle
    /// Where pairing with Apple Passwords stands, or nil while the prompt only
    /// offers it.
    private(set) var pairingStep: BrowserApplePasswordsPairingStep?
    /// What the last pairing step told the person, if anything.
    private(set) var pairingFeedback: BrowserApplePasswordsPairingOutcome?

    @ObservationIgnored private var activeOperationID: UUID?
    @ObservationIgnored private var activeTask: Task<BrowserCredentialOffer, any Error>?
    @ObservationIgnored private var pairingOperationID: UUID?
    /// Who to tell if the person gives up on the code.
    @ObservationIgnored private weak var pairingLoader: (any BrowserCredentialSuggestionLoading)?

    var suggestions: [BrowserCredentialSuggestion] {
        guard case .suggestions(let offer) = phase else { return [] }
        return offer.suggestions
    }

    var codes: [BrowserOneTimeCodeSuggestion] {
        guard case .suggestions(let offer) = phase else { return [] }
        return offer.codes
    }

    var offersPairing: Bool {
        guard case .suggestions(let offer) = phase else { return false }
        return offer.offersApplePasswordsPairing
    }

    var offersOpeningPasswordsApp: Bool {
        guard case .suggestions(let offer) = phase else { return false }
        return offer.offersOpeningPasswordsApp
    }

    var isLoading: Bool {
        phase == .idle || phase == .loading
    }

    var hasFailed: Bool {
        phase == .failed
    }

    /// - Parameters:
    ///   - tab: The tab of the page that asked, where there is one.
    ///   - keepsRows: Whether the rows on show stay until the new ones arrive,
    ///     as a list that looks again does.
    func load(
        _ request: BrowserCredentialFillRequest,
        in spaceID: UUID,
        tab: UUID?,
        keepsRows: Bool = false,
        using loader: any BrowserCredentialSuggestionLoading
    ) async {
        cancelActiveOperation()

        let operationID = UUID()
        activeOperationID = operationID
        if !keepsRows { phase = .loading }

        let task = Task { @MainActor in
            if request.isOneTimeCodeField {
                try await loader.oneTimeCodeOffer(for: request, in: spaceID, tab: tab)
            } else {
                try await loader.credentialOffer(for: request.origin, in: spaceID, tab: tab)
            }
        }
        activeTask = task

        await withTaskCancellationHandler {
            do {
                let loadedOffer = try await task.value
                publish(
                    loadedOffer,
                    usernameHint: request.usernameHint,
                    for: operationID
                )
            } catch {
                publish(error: error, for: operationID)
            }
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() {
        cancelActiveOperation()
        abandonPairing()
        phase = .idle
    }

    // MARK: - Pairing

    /// Has Apple Passwords show a code, then waits for the person to type it.
    func beginPairing(in spaceID: UUID, using loader: any BrowserCredentialSuggestionLoading) async {
        let operationID = UUID()
        pairingOperationID = operationID
        pairingLoader = loader
        pairingFeedback = nil
        pairingStep = .requestingCode
        await requestCode(operationID, in: spaceID, using: loader)
    }

    /// Pairs with `code`, then offers the Space's passwords again. A spent
    /// challenge asks the helper for a fresh code.
    func submitPairingCode(
        _ code: String,
        for request: BrowserCredentialFillRequest,
        in spaceID: UUID,
        tab: UUID?,
        using loader: any BrowserCredentialSuggestionLoading
    ) async {
        let operationID = UUID()
        pairingOperationID = operationID
        pairingStep = .verifying
        let outcome = await loader.completeApplePasswordsPairing(code: code, in: spaceID)
        guard pairingOperationID == operationID else { return }
        pairingFeedback = outcome
        if outcome.isPaired {
            pairingOperationID = nil
            pairingStep = nil
            pairingFeedback = nil
            await load(request, in: spaceID, tab: tab, using: loader)
        } else if outcome.asksForNewCode {
            pairingStep = .requestingCode
            await requestCode(operationID, in: spaceID, using: loader)
        } else {
            pairingStep = outcome.endsPairing ? nil : .enteringCode
        }
    }

    /// The person dismissed the code entry.
    func cancelPairing() {
        abandonPairing()
        pairingFeedback = nil
    }

    /// Stops pairing. If the helper was still waiting for a typed code, tells
    /// it so, as Apple's extension does when its pairing popup closes.
    private func abandonPairing() {
        let helperWaitsForCode = pairingStep == .enteringCode
        let loader = pairingLoader
        pairingOperationID = nil
        pairingStep = nil
        pairingLoader = nil
        guard helperWaitsForCode, let loader else { return }
        Task { @MainActor in await loader.cancelApplePasswordsPairing() }
    }

    private func requestCode(
        _ operationID: UUID, in spaceID: UUID, using loader: any BrowserCredentialSuggestionLoading
    ) async {
        let outcome = await loader.requestApplePasswordsPairingCode(in: spaceID)
        guard pairingOperationID == operationID else { return }
        if outcome.endsPairing || outcome.isPaired {
            pairingStep = nil
            pairingFeedback = outcome
        } else {
            pairingStep = .enteringCode
        }
    }

    private func cancelActiveOperation() {
        activeOperationID = nil
        activeTask?.cancel()
        activeTask = nil
    }

    private func publish(
        _ offer: BrowserCredentialOffer,
        usernameHint: String?,
        for operationID: UUID
    ) {
        guard activeOperationID == operationID else { return }
        guard !Task.isCancelled else {
            finishCancelledOperation(operationID)
            return
        }

        finishOperation(operationID)
        guard !offer.isEmpty else {
            phase = .empty
            return
        }
        var ordered = offer
        ordered.suggestions = Self.prioritizingUsernameHint(usernameHint, in: offer.suggestions)
        phase = .suggestions(ordered)
    }

    private func publish(error: any Error, for operationID: UUID) {
        guard activeOperationID == operationID else { return }
        guard !Task.isCancelled, !(error is CancellationError) else {
            finishCancelledOperation(operationID)
            return
        }

        finishOperation(operationID)
        phase = .failed
    }

    private func finishOperation(_ operationID: UUID) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        activeTask = nil
    }

    private func finishCancelledOperation(_ operationID: UUID) {
        finishOperation(operationID)
        phase = .idle
    }

    private static func prioritizingUsernameHint(
        _ usernameHint: String?,
        in suggestions: [BrowserCredentialSuggestion]
    ) -> [BrowserCredentialSuggestion] {
        guard let usernameHint,
            let matchingIndex = suggestions.firstIndex(where: {
                $0.descriptor.username.caseInsensitiveCompare(usernameHint) == .orderedSame
            }),
            matchingIndex != suggestions.startIndex
        else {
            return suggestions
        }

        var ordered = suggestions
        ordered.insert(ordered.remove(at: matchingIndex), at: ordered.startIndex)
        return ordered
    }
}

enum BrowserCredentialSuggestionPhase: Equatable, Sendable {
    case idle
    case loading
    case empty
    case suggestions(BrowserCredentialOffer)
    case failed
}

/// Where pairing with Apple Passwords stands once the person chose to start it.
enum BrowserApplePasswordsPairingStep: Equatable, Sendable {
    /// Waiting for the helper to show a code.
    case requestingCode
    /// The helper shows a code, and the person types it.
    case enteringCode
    case verifying
}
