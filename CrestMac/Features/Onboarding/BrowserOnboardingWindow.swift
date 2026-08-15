import SwiftUI

struct BrowserOnboardingWindow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore

    @State private var flow: BrowserOnboardingFlow
    @State private var selectedSourceSpaceID: SpaceID?
    @State private var selectedManualSpaceID: SpaceID?
    @State private var customizationSpaceID: SpaceID?

    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore
    ) {
        self.init(
            request: request,
            cloudSync: cloudSync,
            progress: progress,
            flow: BrowserOnboardingFlow(request: request, browser: browser)
        )
    }

    init(
        request: BrowserOnboardingRequest,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        flow: BrowserOnboardingFlow
    ) {
        self.request = request
        self.cloudSync = cloudSync
        self.progress = progress
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
        progress.markCompleted()
        // The launch gate retired the existing browser window. Restore it
        // before asking SwiftUI to open that scene so it can reuse the window.
        BrowserOnboardingLaunchGateWindow.restore()
        openWindow(id: BrowserSceneID.browser.rawValue)
        dismiss()
    }
}

#Preview("Onboarding Window") {
    let fixture = BrowserOnboardingWindowPreviewFixture()
    BrowserOnboardingWindow(
        request: fixture.request,
        cloudSync: fixture.cloudSync,
        progress: fixture.progress,
        flow: fixture.flow
    )
    .frame(width: 980, height: 660)
}
