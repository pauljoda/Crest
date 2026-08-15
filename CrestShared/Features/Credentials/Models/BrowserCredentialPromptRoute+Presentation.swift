import Foundation

extension BrowserCredentialPromptRoute {
    func title(spaceName: String?) -> LocalizedStringResource {
        switch state {
        case .preparing:
            "Checking password…"
        case .failedPreparation:
            "Couldn’t check password"
        case .create, .alreadyStored, .saving(.create), .failedCommit(.create):
            "Save password?"
        case .update, .saving(.update), .failedCommit(.update):
            "Update password?"
        case .saved, .offeringToSystemPasswords, .completedSystemPasswords,
            .failedSystemPasswords:
            savedTitle(spaceName: spaceName)
        }
    }

    var dismissActionTitle: LocalizedStringResource {
        switch dismissAction {
        case .notNow:
            "Not Now"
        case .done:
            "Done"
        }
    }

    func primaryActionTitle(spaceName: String?) -> LocalizedStringResource? {
        guard let primaryAction else { return nil }
        switch primaryAction {
        case .commit(let action):
            return commitTitle(action: action, spaceName: spaceName)
        case .retryCredentialPreparation:
            return "Try Again"
        case .retrySystemPasswords:
            return "Try Passwords Again"
        }
    }

    var busyAccessibilityLabel: LocalizedStringResource? {
        switch busyActivity {
        case .checkingSavedPasswords:
            "Checking saved passwords"
        case .savingPassword:
            "Saving password"
        case .openingSystemPasswords:
            "Opening Passwords"
        case nil:
            nil
        }
    }

    func destinationMetadata(
        spaceName: String?,
        syncsWithICloud: Bool,
        presentation: BrowserCredentialPromptDestinationPresentation
    ) -> BrowserCredentialPromptDestinationMetadata {
        if offersSystemPasswords {
            return BrowserCredentialPromptDestinationMetadata(
                detail: systemPasswordsDestinationDetail(spaceName: spaceName),
                syncStatus: nil
            )
        }

        if syncsWithICloud, presentation == .combinedStatus {
            return BrowserCredentialPromptDestinationMetadata(
                detail: synchronizedDestinationDetail(spaceName: spaceName),
                syncStatus: nil
            )
        }

        return BrowserCredentialPromptDestinationMetadata(
            detail: spaceDestinationDetail(spaceName: spaceName),
            syncStatus: syncsWithICloud ? "Crest iCloud sync on" : nil
        )
    }

    func errorMessage(spaceName: String?) -> LocalizedStringResource? {
        switch state {
        case .failedPreparation:
            "Crest couldn’t check this Space’s saved passwords."
        case .failedCommit:
            credentialSaveFailure(spaceName: spaceName)
        case .failedSystemPasswords:
            systemPasswordsFailure(spaceName: spaceName)
        case .preparing, .create, .update, .alreadyStored, .saving, .saved,
            .offeringToSystemPasswords, .completedSystemPasswords:
            nil
        }
    }

    func crossOriginMessage(
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        subject: BrowserCredentialPromptCrossOriginSubject
    ) -> LocalizedStringResource {
        switch subject {
        case .definiteCredential:
            "The credential belongs to the embedded \(frameOrigin.description) frame, not \(topLevelOrigin.description)."
        case .currentCredential:
            "This credential belongs to the embedded \(frameOrigin.description) frame, not \(topLevelOrigin.description)."
        }
    }

    private func savedTitle(spaceName: String?) -> LocalizedStringResource {
        if let spaceName {
            return "Saved in \(spaceName)"
        }
        return "Saved in this Space"
    }

    private func commitTitle(
        action: BrowserCredentialSavePromptAction,
        spaceName: String?
    ) -> LocalizedStringResource {
        if offersSystemPasswords {
            return switch action {
            case .create:
                "Save & Offer to Passwords"
            case .update:
                "Update & Offer to Passwords"
            }
        }

        switch (action, spaceName) {
        case (.create, .some(let spaceName)):
            return "Save in \(spaceName)"
        case (.update, .some(let spaceName)):
            return "Update in \(spaceName)"
        case (.create, nil):
            return "Save in this Space"
        case (.update, nil):
            return "Update in this Space"
        }
    }

    private func systemPasswordsDestinationDetail(
        spaceName: String?
    ) -> LocalizedStringResource {
        if let spaceName {
            return "Crest saves in \(spaceName) first; Passwords asks separately"
        }
        return "Crest saves in this Space first; Passwords asks separately"
    }

    private func synchronizedDestinationDetail(
        spaceName: String?
    ) -> LocalizedStringResource {
        if let spaceName {
            return "Stored only in \(spaceName), with Crest iCloud sync"
        }
        return "Stored only in this Space, with Crest iCloud sync"
    }

    private func spaceDestinationDetail(
        spaceName: String?
    ) -> LocalizedStringResource {
        if let spaceName {
            return "Stored only in the \(spaceName) Space"
        }
        return "Stored only in this Space"
    }

    private func credentialSaveFailure(
        spaceName: String?
    ) -> LocalizedStringResource {
        if let spaceName {
            return "Crest couldn’t save this password to the \(spaceName) Space."
        }
        return "Crest couldn’t save this password to this Space."
    }

    private func systemPasswordsFailure(
        spaceName: String?
    ) -> LocalizedStringResource {
        if let spaceName {
            return "Saved in \(spaceName). The Passwords offer wasn’t completed."
        }
        return "Saved in this Space. The Passwords offer wasn’t completed."
    }
}
