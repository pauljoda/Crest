import Foundation
import Observation

@Observable
@MainActor
final class BrowserCredentialSuggestionModel {

    private(set) var phase = BrowserCredentialSuggestionPhase.idle

    /// The row the arrow keys have moved to, which Return fills: the first,
    /// the remembered username's when there is one, until the person moves.
    private(set) var selectedIndex = 0

    @ObservationIgnored private var activeOperationID: UUID?
    @ObservationIgnored private var activeTask: Task<[CredentialDescriptor], any Error>?

    var suggestions: [CredentialDescriptor] {
        guard case .suggestions(let suggestions) = phase else { return [] }
        return suggestions
    }

    /// The login Return fills.
    var selectedSuggestion: CredentialDescriptor? {
        suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex] : nil
    }

    var isLoading: Bool {
        phase == .idle || phase == .loading
    }

    var hasFailed: Bool {
        phase == .failed
    }

    func load(
        _ request: BrowserCredentialFillRequest,
        in spaceID: UUID,
        using loader: BrowserStore
    ) async {
        cancelActiveOperation()

        let operationID = UUID()
        activeOperationID = operationID
        phase = .loading

        let task = Task { @MainActor in
            try await loader.credentialSuggestions(for: request.origin, in: spaceID)
        }
        activeTask = task

        await withTaskCancellationHandler {
            do {
                let loadedSuggestions = try await task.value
                publish(
                    loadedSuggestions,
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
        phase = .idle
    }

    /// Moves the selection `step` rows, stopping at either end.
    func moveSelection(by step: Int) {
        guard !suggestions.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + step, 0), suggestions.count - 1)
    }

    private func cancelActiveOperation() {
        activeOperationID = nil
        activeTask?.cancel()
        activeTask = nil
    }

    private func publish(
        _ suggestions: [CredentialDescriptor],
        usernameHint: String?,
        for operationID: UUID
    ) {
        guard activeOperationID == operationID else { return }
        guard !Task.isCancelled else {
            finishCancelledOperation(operationID)
            return
        }

        finishOperation(operationID)
        selectedIndex = 0
        guard !suggestions.isEmpty else {
            phase = .empty
            return
        }
        phase = .suggestions(
            Self.prioritizingUsernameHint(usernameHint, in: suggestions)
        )
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
        in suggestions: [CredentialDescriptor]
    ) -> [CredentialDescriptor] {
        guard let usernameHint,
            let matchingIndex = suggestions.firstIndex(where: {
                $0.username.caseInsensitiveCompare(usernameHint) == .orderedSame
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
    case suggestions([CredentialDescriptor])
    case failed
}
