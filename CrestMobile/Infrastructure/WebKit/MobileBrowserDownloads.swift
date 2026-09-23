import Foundation

/// The download center one browsing mode shares across every window, and the
/// confirmation its risky downloads wait on. The core holds every mode's
/// records; each window shows the records of the profiles it browses.
@MainActor
struct MobileBrowserDownloads {
    // MARK: - Variables

    let center: BrowserDownloadCenter
    let riskConfirmation: MobileDownloadRiskConfirmationCoordinator

    // MARK: - Initializers

    init(
        core: CrestCore,
        browsingMode: BrowserBrowsingMode = .standard,
        permissionCenter: BrowserSitePermissionCenter,
        loadCredential: @escaping BrowserDownloadCenter.CredentialLoader = { _, _ in nil },
        saveCredential: @escaping BrowserDownloadCenter.CredentialSaver = { _, _ in }
    ) {
        let riskConfirmation = MobileDownloadRiskConfirmationCoordinator()
        self.riskConfirmation = riskConfirmation
        center = BrowserDownloadCenter(
            core: core,
            promptForCredentials: { prompt, spaceName in
                await MobileBrowserDialogPresenter.presentHTTPAuthentication(
                    prompt: prompt,
                    spaceName: spaceName
                )
            },
            allowsCredentialSaving: !browsingMode.isPrivate,
            loadCredential: loadCredential,
            saveCredential: saveCredential,
            approveRiskyDownload: { assessment, sourceURL, spaceName, profileID in
                await riskConfirmation.requestApproval(
                    assessment: assessment,
                    sourceURL: sourceURL,
                    spaceName: spaceName,
                    profileID: profileID
                )
            },
            permissionCenter: permissionCenter
        )
    }
}
