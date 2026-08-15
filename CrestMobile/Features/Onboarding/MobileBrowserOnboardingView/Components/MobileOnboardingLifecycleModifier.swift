import SwiftUI

struct MobileOnboardingLifecycleModifier: ViewModifier {
    let request: BrowserOnboardingRequest
    @Bindable var progress: BrowserOnboardingProgressStore
    @Binding var plan: BrowserManualSetupPlan
    @Binding var customizedSpaceID: SpaceID?
    let draftPersistence: MobileOnboardingDraftPersistence
    let existingSession: BrowserSession
    let requestChanged: (BrowserOnboardingRequest) -> Void

    func body(content: Content) -> some View {
        content
            .task {
                if progress.isChecking {
                    await progress.refresh()
                }
            }
            .onChange(of: plan) { _, plan in
                draftPersistence.save(plan)
            }
            .onChange(of: request) { _, request in
                requestChanged(request)
            }
            .interactiveDismissDisabled(request.entryPoint == .firstRun)
            .sheet(item: $customizedSpaceID) { spaceID in
                MobileOnboardingSpaceCustomizationSheet(
                    spaceID: spaceID,
                    plan: $plan,
                    existingSession: existingSession
                )
            }
    }
}

#Preview("Onboarding Lifecycle") {
    @Previewable @State var plan = MobileOnboardingPreviewFixtures.manualPlan
    @Previewable @State var customizedSpaceID: SpaceID?
    let fixture = MobileBrowserPreviewFixture()
    let progress = BrowserOnboardingProgressStore(
        persistence: InMemoryBrowserOnboardingProgressPersistence()
    )
    Color(uiColor: .systemBackground)
        .modifier(
            MobileOnboardingLifecycleModifier(
                request: BrowserOnboardingRequest(
                    entryPoint: .manualSetup,
                    presentationID: UUID(
                        uuid: (
                            0x34, 0xC8, 0x5B, 0x68, 0x41, 0xE4, 0x4A, 0x3C,
                            0xA4, 0xB9, 0x3F, 0x39, 0x72, 0x13, 0x3C, 0x43
                        )
                    )
                ),
                progress: progress,
                plan: $plan,
                customizedSpaceID: $customizedSpaceID,
                draftPersistence: .preview,
                existingSession: fixture.browser.session,
                requestChanged: { _ in }
            )
        )
}
