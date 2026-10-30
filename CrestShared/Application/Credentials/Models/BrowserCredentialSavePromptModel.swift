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
    /// Where this one save goes. Apple Passwords is the default only where the
    /// core offers it for the Space; the choice is never remembered.
    private(set) var destination = CredentialProvider.crestPasswords
    /// Whether the person may switch between Crest's and Apple's passwords.
    private(set) var offersDestinationChoice = false
    /// Whether Apple Passwords is set to never save for the site, so only
    /// Crest's own vault is offered.
    private(set) var appleNeverSaves = false

    @ObservationIgnored private var candidateID: UUID?
    /// What Crest's own vault would ask, kept for when the person picks it.
    @ObservationIgnored private var crestPhase: BrowserCredentialSavePromptPhase = .preparing
    @ObservationIgnored private var choseCrestPasswords = false

    /// The other place the save could go, when there is one.
    var alternateDestination: CredentialProvider? {
        guard offersDestinationChoice else { return nil }
        return destination.keepsSpaceVault ? .applePasswords : .crestPasswords
    }

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
        case .preparing, .alreadyStored, .saved, .sent, .failed(.preparation):
            nil
        }
    }

    var isBusy: Bool {
        if systemPasswordOfferPhase == .offering {
            return true
        }
        return switch phase {
        case .preparing, .saving:
            true
        case .create, .update, .alreadyStored, .saved, .sent, .failed:
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
        in spaceID: UUID,
        tab: UUID?,
        browser: BrowserStore,
        now: Date = .now
    ) async {
        if candidateID != candidate.id { choseCrestPasswords = false }
        candidateID = candidate.id
        phase = .preparing
        systemPasswordOfferPhase = .notRequested
        let crestPhase: BrowserCredentialSavePromptPhase
        do {
            let plan = try await browser.credentialSavePlan(
                for: candidate,
                in: spaceID,
                now: now
            )
            crestPhase = plan.promptPhase
        } catch {
            crestPhase = .failed(.preparation)
        }
        guard !Task.isCancelled, candidateID == candidate.id else { return }
        self.crestPhase = crestPhase
        let answer = await browser.applePasswordsSaveAnswer(for: candidate, in: spaceID, tab: tab)
        guard !Task.isCancelled, candidateID == candidate.id else { return }
        offersDestinationChoice = answer.offerableSupport != nil
        appleNeverSaves = answer.neverSaves
        destination = offersDestinationChoice && !choseCrestPasswords ? .applePasswords : .crestPasswords
        // Apple decides between a new and a changed password, so Crest's own match does not apply.
        phase = destination.keepsSpaceVault ? crestPhase : .create
    }

    /// Switches this one save to `provider`, when it is on offer.
    func choose(_ provider: CredentialProvider) {
        guard provider == alternateDestination, !isBusy else { return }
        destination = provider
        choseCrestPasswords = provider.keepsSpaceVault
        phase = provider.keepsSpaceVault ? crestPhase : .create
    }

    func commit(
        candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        tab: UUID?,
        browser: BrowserStore,
        now: Date = .now
    ) async {
        guard candidateID == candidate.id else { return }
        let action: BrowserCredentialSavePromptAction
        switch phase {
        case .create:
            action = destination.keepsSpaceVault ? .create : .applePasswords
        case .update:
            action = .update
        case .preparing, .alreadyStored, .saving, .saved, .sent, .failed:
            return
        }
        phase = .saving(action)
        do {
            if destination.keepsSpaceVault {
                let result = try await browser.commitCredentialSave(
                    candidate,
                    in: spaceID,
                    now: now
                )
                guard !Task.isCancelled, candidateID == candidate.id else { return }
                phase = .saved(result.disposition)
            } else {
                try await browser.commitApplePasswordsSave(candidate, in: spaceID, tab: tab, now: now)
                guard !Task.isCancelled, candidateID == candidate.id else { return }
                phase = .sent
            }
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

/// Whether the prompt saves a new password or updates a saved one, with the
/// words for each.
struct BrowserCredentialSavePromptAction: Hashable, Sendable {
    // MARK: - Variables

    static let create = BrowserCredentialSavePromptAction(
        name: "create", promptTitle: "Save password?", offerTitle: "Save & Offer to Passwords",
        commitTitle: { spaceName in spaceName.map { "Save in \($0)" } ?? "Save in this Space" },
        failureMessage: { spaceName in
            spaceName.map { "Crest couldn’t save this password to the \($0) Space." }
                ?? "Crest couldn’t save this password to this Space."
        })
    static let update = BrowserCredentialSavePromptAction(
        name: "update", promptTitle: "Update password?", offerTitle: "Update & Offer to Passwords",
        commitTitle: { spaceName in spaceName.map { "Update in \($0)" } ?? "Update in this Space" },
        failureMessage: { spaceName in
            spaceName.map { "Crest couldn’t save this password to the \($0) Space." }
                ?? "Crest couldn’t save this password to this Space."
        })
    /// Offers the password to Apple Passwords, which creates or updates as it sees fit.
    static let applePasswords = BrowserCredentialSavePromptAction(
        name: "applePasswords", promptTitle: "Save password?", offerTitle: "Save to Apple Passwords",
        commitTitle: { _ in "Save to Apple Passwords" },
        failureMessage: { _ in "Crest couldn’t send this password to Apple Passwords." })

    let name: String

    /// The prompt's question.
    let promptTitle: LocalizedStringResource

    /// The commit button's title when the save also offers the password to
    /// the system's Passwords app.
    let offerTitle: LocalizedStringResource

    /// The commit button's title, naming the Space the password is saved in.
    let commitTitle: @Sendable (_ spaceName: String?) -> LocalizedStringResource

    /// What the prompt says when the save fails.
    let failureMessage: @Sendable (_ spaceName: String?) -> LocalizedStringResource

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialSavePromptAction, rhs: BrowserCredentialSavePromptAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
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
    /// The password was handed to Apple Passwords, whose own alert asks the
    /// person to confirm. Whether it was saved is not known.
    case sent
    case failed(BrowserCredentialSavePromptFailure)
}

enum BrowserSystemPasswordOfferPhase: Equatable, Sendable {
    case notRequested
    case offering
    case completed
    case failed
}
