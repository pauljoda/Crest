import Foundation
import Sparkle

struct BrowserSoftwareUpdateMetadata: Equatable, Sendable {
    let title: String
    let version: String?
    let build: String
    let releaseNotes: String?
    let informationURL: URL?

    init(
        title: String,
        version: String?,
        build: String,
        releaseNotes: String?,
        informationURL: URL?
    ) {
        self.title = title
        self.version = version
        self.build = build
        self.releaseNotes = releaseNotes
        self.informationURL = informationURL
    }

    init(appcastItem: SUAppcastItem) {
        title =
            appcastItem.title
            ?? "Crest \(appcastItem.displayVersionString)"
        version = appcastItem.displayVersionString
        build = appcastItem.versionString
        releaseNotes = appcastItem.itemDescription
        informationURL = appcastItem.infoURL
    }
}

/// Adapts Sparkle's silent automatic-update delegate callbacks to the same
/// observable state used by Crest's manual user driver and sidebar widget.
@MainActor
final class BrowserAutomaticSoftwareUpdatePresenter {
    private let model: BrowserSoftwareUpdateModel
    private var activeUpdate: BrowserSoftwareUpdateMetadata?

    init(model: BrowserSoftwareUpdateModel) {
        self.model = model
    }

    func downloadDidBegin(_ update: BrowserSoftwareUpdateMetadata) {
        guard
            model.presentAutomaticDownload(
                title: update.title,
                version: update.version,
                build: update.build,
                releaseNotes: update.releaseNotes,
                informationURL: update.informationURL
            )
        else { return }
        activeUpdate = update
    }

    func extractionDidBegin(_ update: BrowserSoftwareUpdateMetadata) {
        if activeUpdate?.build != update.build {
            downloadDidBegin(update)
        }
        guard activeUpdate?.build == update.build else { return }
        model.presentExtraction()
    }

    func installationDidBecomeReady(
        _ update: BrowserSoftwareUpdateMetadata,
        installAndRelaunch: @escaping () -> Void
    ) {
        activeUpdate = update
        model.presentAutomaticUpdateReady(
            title: update.title,
            version: update.version,
            build: update.build,
            releaseNotes: update.releaseNotes,
            informationURL: update.informationURL,
            installAndRelaunch: installAndRelaunch
        )
    }

    func updateDidFail(_ error: any Error) {
        guard let activeUpdate else { return }
        self.activeUpdate = nil
        let error = error as NSError
        let message = [
            error.localizedDescription,
            error.localizedRecoverySuggestion,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        model.presentAutomaticUpdateFailure(
            title: activeUpdate.title,
            version: activeUpdate.version,
            build: activeUpdate.build,
            message: message
        )
    }
}

@MainActor
final class BrowserSoftwareUpdateUserDriver: NSObject, SPUUserDriver,
    SPUUpdaterDelegate
{
    let model: BrowserSoftwareUpdateModel
    var channel: BrowserSoftwareUpdateChannel
    var updateCycleDidFinish: (() -> Void)?
    private let feedURLOverride: URL?
    private let automaticUpdatePresenter: BrowserAutomaticSoftwareUpdatePresenter

    init(
        model: BrowserSoftwareUpdateModel,
        channel: BrowserSoftwareUpdateChannel,
        feedURLOverride: URL? = nil
    ) {
        self.model = model
        self.channel = channel
        self.feedURLOverride = feedURLOverride
        self.automaticUpdatePresenter = BrowserAutomaticSoftwareUpdatePresenter(
            model: model
        )
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
            build: appcastItem.versionString,
            releaseNotes: appcastItem.itemDescription,
            informationURL: appcastItem.infoURL,
            isInformationOnly: appcastItem.isInformationOnlyUpdate,
            suppressesWindowPresentation: !state.userInitiated,
            install: { reply(.install) },
            skip: { reply(.skip) },
            dismiss: { reply(.dismiss) }
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

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        updateCycleDidFinish?()
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        automaticUpdatePresenter.downloadDidBegin(
            BrowserSoftwareUpdateMetadata(appcastItem: item)
        )
    }

    func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: any Error
    ) {
        automaticUpdatePresenter.updateDidFail(error)
    }

    func updater(
        _ updater: SPUUpdater,
        willExtractUpdate item: SUAppcastItem
    ) {
        automaticUpdatePresenter.extractionDidBegin(
            BrowserSoftwareUpdateMetadata(appcastItem: item)
        )
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        automaticUpdatePresenter.installationDidBecomeReady(
            BrowserSoftwareUpdateMetadata(appcastItem: item),
            installAndRelaunch: immediateInstallHandler
        )
        // Crest owns the immediate-restart affordance. Sparkle still installs
        // this prepared update whenever the application terminates normally.
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        automaticUpdatePresenter.updateDidFail(error)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.allowedSparkleChannels
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLOverride?.absoluteString ?? channel.customFeedURL?.absoluteString
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
