import Foundation
import Sparkle

@MainActor
final class BrowserSoftwareUpdateUserDriver: NSObject, SPUUserDriver,
    SPUUpdaterDelegate
{
    let model: BrowserSoftwareUpdateModel
    var channel: BrowserSoftwareUpdateChannel

    init(
        model: BrowserSoftwareUpdateModel,
        channel: BrowserSoftwareUpdateChannel
    ) {
        self.model = model
        self.channel = channel
        super.init()
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void
    ) {
        model.presentPermissionRequest { isEnabled in
            reply(
                SUUpdatePermissionResponse(
                    automaticUpdateChecks: isEnabled,
                    sendSystemProfile: false
                )
            )
        }
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        model.presentChecking(cancellation: cancellation)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void
    ) {
        model.presentUpdate(
            title: appcastItem.title
                ?? "Crest \(appcastItem.displayVersionString)",
            version: appcastItem.displayVersionString,
            releaseNotes: appcastItem.itemDescription,
            informationURL: appcastItem.infoURL,
            isInformationOnly: appcastItem.isInformationOnlyUpdate,
            install: { reply(.install) },
            dismiss: { reply(.dismiss) },
            skip: { reply(.skip) }
        )
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard let releaseNotes = String(data: downloadData.data, encoding: .utf8)
        else {
            model.presentReleaseNotesFailure(
                "Release notes were downloaded in an unsupported text encoding."
            )
            return
        }
        model.setReleaseNotes(releaseNotes)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        model.presentReleaseNotesFailure(
            "Release notes could not be loaded: \(error.localizedDescription)"
        )
    }

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        model.presentNoUpdate(
            message: noUpdateMessage(error),
            acknowledgement: acknowledgement
        )
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        model.presentError(
            message: updateErrorMessage(error),
            acknowledgement: acknowledgement
        )
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        model.presentDownload(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(
        _ expectedContentLength: UInt64
    ) {
        model.setExpectedDownloadLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        model.receiveDownloadedBytes(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        model.presentExtraction()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.setExtractionProgress(progress)
    }

    func showReady(
        toInstallAndRelaunch reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void
    ) {
        model.presentReadyToInstall(
            install: { reply(.install) },
            dismiss: { reply(.dismiss) },
            cancel: { reply(.skip) }
        )
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        model.presentInstalling(
            applicationTerminated: applicationTerminated,
            retryTermination: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        model.presentInstalled(
            relaunched: relaunched,
            acknowledgement: acknowledgement
        )
    }

    func dismissUpdateInstallation() {
        model.dismissInstallation()
    }

    func showUpdateInFocus() {
        model.focus()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.allowedSparkleChannels
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        channel.customFeedURL?.absoluteString
    }

    private func noUpdateMessage(_ error: any Error) -> String {
        let error = error as NSError
        return [error.localizedDescription, error.localizedRecoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func updateErrorMessage(_ error: any Error) -> String {
        let error = error as NSError
        return [error.localizedDescription, error.localizedRecoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
