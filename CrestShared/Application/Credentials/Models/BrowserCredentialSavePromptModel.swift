import Foundation
import Observation

/// Owns the platform-neutral save/update prompt lifecycle without retaining
/// the submitted secret. SwiftUI views keep the candidate page-owned and use
/// this model only for the decision and persistence phases.
@Observable
@MainActor
final class BrowserCredentialSavePromptModel {
    private(set) var phase: BrowserCredentialSavePromptPhase = .preparing
    private(set) var systemPasswordOfferPhase = BrowserSystemPasswordOfferPhase.notRequested

    @ObservationIgnored private var candidateID: UUID?

    var confirmationAction: BrowserCredentialSavePromptAction? {
        switch phase {
        case .create:
            .create
        case .update:
            .update
        case .saving(let action):
            action
        case .failed(.commit(let action)):
            action
        case .preparing, .alreadyStored, .saved, .failed(.preparation):
            nil
        }
    }

    var canCommit: Bool {
        phase == .create || phase == .update
    }

    var isBusy: Bool {
        if systemPasswordOfferPhase == .offering {
            return true
        }
        return switch phase {
        case .preparing, .saving:
            true
        case .create, .update, .alreadyStored, .saved, .failed:
            false
        }
    }

    var hasFailure: Bool {
        if case .failed = phase {
            return true
        }
        return false
    }

    func prepare(
        candidate: BrowserCredentialSaveCandidate,
        in spaceID: SpaceID,
        browser: BrowserStore,
        now: Date = .now
    ) async {
        candidateID = candidate.id
        phase = .preparing
        systemPasswordOfferPhase = .notRequested
        do {
            let plan = try await browser.credentialSavePlan(
                for: candidate,
                in: spaceID,
                now: now
            )
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            switch plan {
            case .create:
                phase = .create
            case .update:
                phase = .update
            case .alreadyStored:
                phase = .alreadyStored
            }
        } catch {
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            phase = .failed(.preparation)
        }
    }

    func commit(
        candidate: BrowserCredentialSaveCandidate,
        in spaceID: SpaceID,
        browser: BrowserStore,
        now: Date = .now
    ) async {
        guard candidateID == candidate.id else { return }
        let action: BrowserCredentialSavePromptAction
        switch phase {
        case .create:
            action = .create
        case .update:
            action = .update
        case .preparing, .alreadyStored, .saving, .saved, .failed:
            return
        }
        phase = .saving(action)
        do {
            let result = try await browser.commitCredentialSave(
                candidate,
                in: spaceID,
                now: now
            )
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            phase = .saved(result.disposition)
        } catch {
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            phase = .failed(.commit(action))
        }
    }

    func offerToSystemPasswords(
        _ offer: @MainActor () async throws -> Void
    ) async {
        guard case .saved = phase,
            systemPasswordOfferPhase != .offering,
            systemPasswordOfferPhase != .completed
        else {
            return
        }
        let expectedCandidateID = candidateID
        systemPasswordOfferPhase = .offering
        do {
            try await offer()
            guard !Task.isCancelled, candidateID == expectedCandidateID else { return }
            systemPasswordOfferPhase = .completed
        } catch is CancellationError {
            guard candidateID == expectedCandidateID else { return }
            systemPasswordOfferPhase = .notRequested
        } catch {
            guard candidateID == expectedCandidateID else { return }
            systemPasswordOfferPhase = .failed
        }
    }
}

enum BrowserCredentialSavePromptAction: Equatable, Sendable {
    case create
    case update
}

enum BrowserCredentialSavePromptFailure: Equatable, Sendable {
    case preparation
    case commit(BrowserCredentialSavePromptAction)
}

enum BrowserCredentialSavePromptPhase: Equatable, Sendable {
    case preparing
    case create
    case update
    case alreadyStored
    case saving(BrowserCredentialSavePromptAction)
    case saved(BrowserCredentialSaveDisposition)
    case failed(BrowserCredentialSavePromptFailure)
}

enum BrowserSystemPasswordOfferPhase: Equatable, Sendable {
    case notRequested
    case offering
    case completed
    case failed
}
