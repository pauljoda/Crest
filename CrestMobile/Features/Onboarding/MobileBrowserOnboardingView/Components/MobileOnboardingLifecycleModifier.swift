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
