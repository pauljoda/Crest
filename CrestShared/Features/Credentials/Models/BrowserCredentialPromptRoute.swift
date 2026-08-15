import Foundation

/// Exhaustively maps the credential workflow into platform-neutral prompt presentation.
struct BrowserCredentialPromptRoute: Equatable, Sendable {

    let state: BrowserCredentialPromptState
    let offersSystemPasswords: Bool

    init(
        phase: BrowserCredentialSavePromptPhase,
        systemPasswordOfferPhase: BrowserSystemPasswordOfferPhase,
        offersSystemPasswords: Bool
    ) {
        self.offersSystemPasswords = offersSystemPasswords

        guard case .saved = phase else {
            state = Self.state(for: phase)
            return
        }

        state =
            switch systemPasswordOfferPhase {
            case .notRequested:
                Self.state(for: phase)
            case .offering:
                .offeringToSystemPasswords
            case .completed:
                .completedSystemPasswords
            case .failed:
                .failedSystemPasswords
            }
    }

    var primaryAction: BrowserCredentialPromptPrimaryAction? {
        switch state {
        case .create:
            .commit(.create)
        case .update:
            .commit(.update)
        case .failedPreparation, .failedCommit:
            .retryCredentialPreparation
        case .failedSystemPasswords:
            .retrySystemPasswords
        case .preparing, .alreadyStored, .saving, .saved,
            .offeringToSystemPasswords, .completedSystemPasswords:
            nil
        }
    }

    var dismissAction: BrowserCredentialPromptDismissAction {
        switch state {
        case .saved, .offeringToSystemPasswords, .completedSystemPasswords,
            .failedSystemPasswords:
            .done
        case .preparing, .create, .update, .alreadyStored, .saving,
            .failedPreparation, .failedCommit:
            .notNow
        }
    }

    var busyActivity: BrowserCredentialPromptBusyActivity? {
        switch state {
        case .preparing:
            .checkingSavedPasswords
        case .saving:
            .savingPassword
        case .offeringToSystemPasswords:
            .openingSystemPasswords
        case .create, .update, .alreadyStored, .saved, .failedPreparation,
            .failedCommit, .completedSystemPasswords, .failedSystemPasswords:
            nil
        }
    }

    var isBusy: Bool {
        busyActivity != nil
    }

    private static func state(for phase: BrowserCredentialSavePromptPhase) -> BrowserCredentialPromptState {
        switch phase {
        case .preparing:
            .preparing
        case .create:
            .create
        case .update:
            .update
        case .alreadyStored:
            .alreadyStored
        case .saving(let action):
            .saving(action)
        case .saved(let disposition):
            .saved(disposition)
        case .failed(.preparation):
            .failedPreparation
        case .failed(.commit(let action)):
            .failedCommit(action)
        }
    }

}
