import Foundation
import Observation

@MainActor
@Observable
final class BrowserSoftwareUpdateModel {
    private(set) var phase = BrowserSoftwareUpdatePhase.idle
    private(set) var presentationRevision = 0
    private(set) var dismissalRevision = 0
    private(set) var updateTitle: String?
    private(set) var updateVersion: String?
    private(set) var updateBuild: String?
    private(set) var releaseNotes: String?
    private(set) var informationURL: URL?
    private(set) var message: String?
    private(set) var progress: Double?
    private(set) var isInformationOnly = false
    private(set) var didRelaunch = false
    private(set) var canRetryTermination = false
    private(set) var isFixture = false

    @ObservationIgnored private weak var widgetSource: BrowserSoftwareUpdateWidgetSource?

    @ObservationIgnored private var expectedDownloadLength: UInt64?
    @ObservationIgnored private var receivedDownloadLength: UInt64 = 0
    @ObservationIgnored private var permissionResponse: ((Bool) -> Void)?
    @ObservationIgnored private var cancellation: (() -> Void)?
    @ObservationIgnored private var install: (() -> Void)?
    @ObservationIgnored private var skip: (() -> Void)?
    @ObservationIgnored private var dismiss: (() -> Void)?
    @ObservationIgnored private var installAndRelaunch: (() -> Void)?
    @ObservationIgnored private var retryTermination: (() -> Void)?
    @ObservationIgnored private var acknowledgement: (() -> Void)?
    @ObservationIgnored private var suppressesWindowPresentation = false

    init(widgetSource: BrowserSoftwareUpdateWidgetSource? = nil) {
        self.widgetSource = widgetSource
        widgetSource?.bind(self)
    }

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
        publishWidgetState()
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
        build: String? = nil,
        releaseNotes: String? = nil,
        informationURL: URL? = nil,
        isInformationOnly: Bool,
        isFixture: Bool = false,
        suppressesWindowPresentation: Bool = false,
        install: @escaping () -> Void,
        skip: @escaping () -> Void,
        dismiss: @escaping () -> Void = {}
    ) {
        resetCallbacks()
        phase = .updateAvailable
        updateTitle = title
        updateVersion = version
        updateBuild = build
        self.releaseNotes = releaseNotes
        self.informationURL = informationURL
        self.isInformationOnly = isInformationOnly
        self.isFixture = isFixture
        self.suppressesWindowPresentation = suppressesWindowPresentation
        self.install = install
        self.skip = skip
        self.dismiss = dismiss
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
        publishWidgetState()
    }

    func receiveDownloadedBytes(_ length: UInt64) {
        let addition = receivedDownloadLength.addingReportingOverflow(length)
        receivedDownloadLength = addition.overflow ? .max : addition.partialValue
        updateDownloadProgress()
        publishWidgetState()
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
        publishWidgetState()
    }

    func presentReadyToInstall(
        install: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        phase = .readyToInstall
        message = "The update is ready. Crest will relaunch to finish installing it."
        installAndRelaunch = install
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
        skip = nil
        phase = .downloading
        publishWidgetState()
        install()
    }

    /// Ends only an undownloaded available-update choice so Sparkle can run a
    /// fresh feed check. This is intentionally distinct from `.skip`, which
    /// persists a version exclusion, and is unavailable once download or
    /// installation work has begun.
    @discardableResult
    func beginRefreshingAvailableUpdate(
        suppressesWindowPresentation: Bool
    ) -> Bool {
        guard phase == .updateAvailable, let dismiss else { return false }
        resetCallbacks()
        phase = .checking
        message = "Checking whether a newer Crest update is available…"
        self.suppressesWindowPresentation = suppressesWindowPresentation
        present()
        dismiss()
        return true
    }

    func finishRefreshIfNeeded() {
        guard phase == .checking else { return }
        reset()
    }

    /// Hides only the update window. The pending Sparkle choice stays alive so
    /// the global widget remains actionable until the user installs or skips
    /// this exact build.
    func deferUpdatePresentation() {
        guard phase == .updateAvailable || phase == .readyToInstall,
            !suppressesWindowPresentation
        else { return }
        suppressesWindowPresentation = true
        dismissalRevision &+= 1
        publishWidgetState()
    }

    func skipUpdate() {
        let skip = self.skip
        self.skip = nil
        install = nil
        installAndRelaunch = nil
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
        skip = nil
        dismiss = nil
        phase = .installing
        publishWidgetState()
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
            deferUpdatePresentation()
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
        suppressesWindowPresentation = false
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
        if !suppressesWindowPresentation {
            presentationRevision &+= 1
        }
        publishWidgetState()
    }

    private func reset() {
        resetCallbacks()
        phase = .idle
        updateTitle = nil
        updateVersion = nil
        updateBuild = nil
        releaseNotes = nil
        informationURL = nil
        message = nil
        progress = nil
        isInformationOnly = false
        isFixture = false
        suppressesWindowPresentation = false
        didRelaunch = false
        canRetryTermination = false
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        publishWidgetState()
    }

    private func resetCallbacks() {
        permissionResponse = nil
        cancellation = nil
        install = nil
        skip = nil
        dismiss = nil
        installAndRelaunch = nil
        retryTermination = nil
        canRetryTermination = false
        acknowledgement = nil
    }

    var sidebarWidgetSnapshot: BrowserSoftwareUpdateWidgetSnapshot? {
        let widgetPhase: BrowserSoftwareUpdateWidgetPhase
        switch phase {
        case .checking:
            guard updateVersion != nil || updateBuild != nil else { return nil }
            widgetPhase = .checking
        case .updateAvailable:
            widgetPhase = .available
        case .downloading:
            widgetPhase = .downloading
        case .extracting:
            widgetPhase = .extracting
        case .readyToInstall:
            widgetPhase = .readyToInstall
        case .installing:
            widgetPhase = .installing
        case .failed:
            guard updateVersion != nil || updateBuild != nil else { return nil }
            widgetPhase = .failed
        case .idle, .permission, .upToDate, .installed:
            return nil
        }
        return BrowserSoftwareUpdateWidgetSnapshot(
            phase: widgetPhase,
            title: updateTitle ?? "Crest Update",
            version: updateVersion,
            build: updateBuild,
            message: message,
            progress: progress,
            isInformationOnly: isInformationOnly,
            isFixture: isFixture
        )
    }

    private func publishWidgetState() {
        widgetSource?.publish(sidebarWidgetSnapshot)
    }
}
