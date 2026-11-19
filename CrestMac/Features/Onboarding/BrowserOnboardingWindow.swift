import SwiftUI

struct BrowserOnboardingWindow: View {
    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let spaceAccess: BrowserSpaceAccessController
    /// Closes the window setup shows in.
    private let closeWindow: () -> Void
    /// Hands setup over to Crest once it finished: the window setup was
    /// opened from, or the launch it held back, comes in behind setup, which
    /// then fades away over it and closes.
    private let openBrowser: () -> Void

    @State private var flow: BrowserOnboardingFlow
    /// How long the welcome has waited on iCloud's check.
    @State private var cloudWait = BrowserOnboardingCloudWait()
    /// Whether setup finished and its preview is growing into the window
    /// Crest opens in its place.
    @State private var isTakingOver = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController,
        extensionInstaller: (any BrowserImportedExtensionInstalling)?,
        closeWindow: @escaping () -> Void,
        openBrowser: @escaping () -> Void
    ) {
        self.init(
            request: request,
            cloudSync: cloudSync,
            progress: progress,
            spaceAccess: spaceAccess,
            flow: BrowserOnboardingFlow(request: request, browser: browser, extensionInstaller: extensionInstaller),
            closeWindow: closeWindow, openBrowser: openBrowser
        )
    }

    init(
        request: BrowserOnboardingRequest,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController,
        flow: BrowserOnboardingFlow,
        closeWindow: @escaping () -> Void,
        openBrowser: @escaping () -> Void
    ) {
        self.request = request
        self.cloudSync = cloudSync
        self.progress = progress
        self.spaceAccess = spaceAccess
        self.closeWindow = closeWindow
        self.openBrowser = openBrowser
        _flow = State(initialValue: flow)
    }

    var body: some View {
        BrowserSetupWindowContent(
            request: request,
            cloudSync: cloudSync,
            progress: progress,
            flow: flow,
            cloudWait: cloudWait,
            isTakingOver: isTakingOver,
            close: closeWindow,
            startBrowsing: startBrowsing,
            openCrest: openCrest
        )
        .environment(flow.browser.core)
    }

    /// Applies the import setup holds, then finishes setup, carrying `edits`,
    /// what the person changed in the preview's tabs and folders, and opens
    /// Crest.
    private func startBrowsing(_ edits: BrowserSetupCopyEdits?) {
        flow.startBrowsing(progress: progress, spaceAccess: spaceAccess, carrying: edits, onCompleted: takeOver)
    }

    private func openCrest() {
        flow.completeSetup(progress: progress, spaceAccess: spaceAccess, onCompleted: takeOver)
    }

    /// Grows the preview over the steps until it fills the window, then hands
    /// over to Crest, which opens in the window's place as setup fades away.
    private func takeOver() {
        guard !reduceMotion else {
            isTakingOver = true
            openBrowser()
            return
        }
        withAnimation(CrestMotion.onboardingStep) { isTakingOver = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CrestMotion.onboardingStepTransition))
            openBrowser()
        }
    }
}

#Preview("Onboarding Window") {
    let fixture = BrowserOnboardingWindowPreviewFixture()
    BrowserOnboardingWindow(
        request: fixture.request,
        cloudSync: fixture.cloudSync,
        progress: fixture.progress,
        spaceAccess: fixture.spaceAccess,
        flow: fixture.flow,
        closeWindow: {},
        openBrowser: {}
    )
    .frame(width: 980, height: 660)
}
