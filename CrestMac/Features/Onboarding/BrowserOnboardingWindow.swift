import SwiftUI

struct BrowserOnboardingWindow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let spaceAccess: BrowserSpaceAccessController

    @State private var flow: BrowserOnboardingFlow
    @State private var selectedSourceSpaceID: SpaceID?
    @State private var selectedManualSpaceID: SpaceID?
    @State private var customizationSpaceID: SpaceID?

    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.init(
            request: request,
            cloudSync: cloudSync,
            progress: progress,
            spaceAccess: spaceAccess,
            flow: BrowserOnboardingFlow(request: request, browser: browser)
        )
    }

    init(
        request: BrowserOnboardingRequest,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        spaceAccess: BrowserSpaceAccessController,
        flow: BrowserOnboardingFlow
    ) {
        self.request = request
        self.cloudSync = cloudSync
        self.progress = progress
        self.spaceAccess = spaceAccess
        _flow = State(initialValue: flow)
        _selectedSourceSpaceID = State(initialValue: nil)
        _selectedManualSpaceID = State(
            initialValue: flow.manualPlan?.spaces.first?.id
        )
        _customizationSpaceID = State(initialValue: nil)
    }

    var body: some View {
        BrowserOnboardingWindowContent(
            request: request,
            cloudSync: cloudSync,
            progress: progress,
            flow: flow,
            selectedSourceSpaceID: $selectedSourceSpaceID,
            selectedManualSpaceID: $selectedManualSpaceID,
            customizationSpaceID: $customizationSpaceID,
            close: { dismiss() },
            openCrest: openCrest
        )
    }

    private func openCrest() {
        let reusesLaunchWindow = progress.isLaunchGateActive
        flow.completeSetup(progress: progress, spaceAccess: spaceAccess) {
            // Completing the gate turns its existing WindowGroup window into
            // the browser. Opening the scene again creates a second window.
            BrowserOnboardingLaunchGateWindow.restore()
            if !reusesLaunchWindow { openWindow(id: BrowserSceneID.browser.rawValue) }
            dismiss()
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
        flow: fixture.flow
    )
    .frame(width: 980, height: 660)
}
