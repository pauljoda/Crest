import Foundation
import Observation

@MainActor
@Observable
final class BrowserSoftwareUpdateModel {
    private(set) var phase = BrowserSoftwareUpdatePhase.idle
    private(set) var presentationRevision = 0
    private(set) var updateTitle: String?
    private(set) var updateVersion: String?
    private(set) var releaseNotes: String?
    private(set) var informationURL: URL?
    private(set) var message: String?
    private(set) var progress: Double?
    private(set) var isInformationOnly = false
    private(set) var didRelaunch = false
    private(set) var canRetryTermination = false

    @ObservationIgnored private var expectedDownloadLength: UInt64?
    @ObservationIgnored private var receivedDownloadLength: UInt64 = 0
    @ObservationIgnored private var permissionResponse: ((Bool) -> Void)?
    @ObservationIgnored private var cancellation: (() -> Void)?
    @ObservationIgnored private var install: (() -> Void)?
    @ObservationIgnored private var dismiss: (() -> Void)?
    @ObservationIgnored private var skip: (() -> Void)?
    @ObservationIgnored private var installAndRelaunch: (() -> Void)?
    @ObservationIgnored private var retryTermination: (() -> Void)?
    @ObservationIgnored private var acknowledgement: (() -> Void)?

    func presentPermissionRequest(response: @escaping (Bool) -> Void) {
        resetCallbacks()
        phase = .permission
        message = "Crest can check for updates automatically without sending a system profile."
        permissionResponse = response
        present()
    }

    func chooseAutomaticChecks(_ isEnabled: Bool) {
        let response = permissionResponse
        permissionResponse = nil
        response?(isEnabled)
        phase = .idle
    }

    func presentChecking(cancellation: @escaping () -> Void) {
        resetCallbacks()
        phase = .checking
        message = "Checking for a newer version of Crest…"
        self.cancellation = cancellation
        present()
    }

    func presentUpdate(
        title: String,
        version: String?,
        releaseNotes: String? = nil,
        informationURL: URL? = nil,
        isInformationOnly: Bool,
        install: @escaping () -> Void,
        dismiss: @escaping () -> Void,
        skip: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .updateAvailable
        updateTitle = title
        updateVersion = version
        self.releaseNotes = releaseNotes
        self.informationURL = informationURL
        self.isInformationOnly = isInformationOnly
        self.install = install
        self.dismiss = dismiss
        self.skip = skip
        message =
            isInformationOnly
            ? "This release is available from the Crest website."
            : "A new version of Crest is ready to download."
        present()
    }

    func setReleaseNotes(_ releaseNotes: String) {
        self.releaseNotes = releaseNotes
    }

    func presentReleaseNotesFailure(_ description: String) {
        guard releaseNotes == nil else { return }
        releaseNotes = description
    }

    func presentNoUpdate(
        message: String,
        acknowledgement: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .upToDate
        self.message = message
        self.acknowledgement = acknowledgement
        present()
    }

    func presentError(
        message: String,
        acknowledgement: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .failed
        self.message = message
        self.acknowledgement = acknowledgement
        present()
    }

    func presentDownload(cancellation: @escaping () -> Void) {
        phase = .downloading
        message = "Downloading the update…"
        progress = nil
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        self.cancellation = cancellation
        present()
    }

    func setExpectedDownloadLength(_ length: UInt64) {
        expectedDownloadLength = length > 0 ? length : nil
        updateDownloadProgress()
    }

    func receiveDownloadedBytes(_ length: UInt64) {
        let addition = receivedDownloadLength.addingReportingOverflow(length)
        receivedDownloadLength = addition.overflow ? .max : addition.partialValue
        updateDownloadProgress()
    }

    func presentExtraction() {
        phase = .extracting
        message = "Preparing the update…"
        progress = nil
        cancellation = nil
        present()
    }

    func setExtractionProgress(_ progress: Double) {
        self.progress = min(max(progress, 0), 1)
    }

    func presentReadyToInstall(
        install: @escaping () -> Void,
        dismiss: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        phase = .readyToInstall
        message = "The update is ready. Crest will relaunch to finish installing it."
        installAndRelaunch = install
        self.dismiss = dismiss
        skip = cancel
        present()
    }

    func presentInstalling(
        applicationTerminated: Bool,
        retryTermination: @escaping () -> Void
    ) {
        phase = .installing
        message =
            applicationTerminated
            ? "Installing the update…"
            : "Waiting for Crest to quit before installing…"
        self.retryTermination = applicationTerminated ? nil : retryTermination
        canRetryTermination = !applicationTerminated
        present()
    }

    func presentInstalled(
        relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .installed
        didRelaunch = relaunched
        message =
            relaunched
            ? "Crest was updated and relaunched successfully."
            : "Crest was updated successfully."
        self.acknowledgement = acknowledgement
        present()
    }

    func installUpdate() {
        guard !isInformationOnly, let install else { return }
        self.install = nil
        phase = .downloading
        install()
    }

    func dismissUpdate() {
        let dismiss = self.dismiss
        self.dismiss = nil
        dismiss?()
        reset()
    }

    func skipUpdate() {
        let skip = self.skip
        self.skip = nil
        skip?()
        reset()
    }

    func cancelCurrentOperation() {
        let cancellation = self.cancellation
        self.cancellation = nil
        cancellation?()
        reset()
    }

    func installAndRelaunchNow() {
        let reply = installAndRelaunch
        installAndRelaunch = nil
        phase = .installing
        reply?()
    }

    func retryApplicationTermination() {
        retryTermination?()
    }

    func acknowledge() {
        let acknowledgement = self.acknowledgement
        self.acknowledgement = nil
        acknowledgement?()
        reset()
    }

    func closePresentation() {
        switch phase {
        case .permission:
            chooseAutomaticChecks(false)
        case .checking, .downloading:
            cancelCurrentOperation()
        case .updateAvailable, .readyToInstall:
            dismissUpdate()
        case .upToDate, .failed, .installed:
            acknowledge()
        case .idle, .extracting, .installing:
            break
        }
    }

    func dismissInstallation() {
        reset()
    }

    func focus() {
        present()
    }

    private func updateDownloadProgress() {
        guard let expectedDownloadLength else {
            progress = nil
            return
        }
        progress = min(
            Double(receivedDownloadLength) / Double(expectedDownloadLength),
            1
        )
    }

    private func present() {
        presentationRevision &+= 1
    }

    private func reset() {
        resetCallbacks()
        phase = .idle
        updateTitle = nil
        updateVersion = nil
        releaseNotes = nil
        informationURL = nil
        message = nil
        progress = nil
        isInformationOnly = false
        didRelaunch = false
        canRetryTermination = false
        expectedDownloadLength = nil
        receivedDownloadLength = 0
    }

    private func resetCallbacks() {
        permissionResponse = nil
        cancellation = nil
        install = nil
        dismiss = nil
        skip = nil
        installAndRelaunch = nil
        retryTermination = nil
        canRetryTermination = false
        acknowledgement = nil
    }
}
