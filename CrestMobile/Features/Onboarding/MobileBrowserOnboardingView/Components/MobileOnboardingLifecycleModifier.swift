import SwiftUI

struct MobileOnboardingLifecycleModifier: ViewModifier {
    let request: BrowserOnboardingRequest
    @Bindable var progress: BrowserOnboardingProgressStore
    @Binding var plan: BrowserManualSetupPlan
    @Binding var customizedSpaceID: SpaceID?
    let draftPersistence: MobileOnboardingDraftPersistence
    let browser: BrowserStore
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
            .sheet(item: customizedDraft) { draft in
                MobileOnboardingSpaceCustomizationSheet(
                    spaceID: draft.id,
                    plan: $plan,
                    browser: browser
                )
            }
    }

    /// The draft of the Space being customized, which presents its sheet.
    private var customizedDraft: Binding<BrowserManualSetupSpaceDraft?> {
        Binding(
            get: { customizedSpaceID.flatMap { id in plan.spaces.first { $0.id == id } } },
            set: { customizedSpaceID = $0?.id })
    }
}
