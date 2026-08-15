import SwiftUI

struct BrowserOnboardingWindowContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let flow: BrowserOnboardingFlow
    @Binding var selectedSourceSpaceID: SpaceID?
    @Binding var selectedManualSpaceID: SpaceID?
    @Binding var customizationSpaceID: SpaceID?
    let close: () -> Void
    let openCrest: () -> Void

    var body: some View {
        ZStack {
            BrowserOnboardingBackdrop()

            VStack(spacing: 0) {
                BrowserOnboardingProgressHeader(step: flow.step)
                if let customizationSpaceID, let plan = flow.plan {
                    BrowserImportSpaceCustomizationView(
                        plan: planBinding(fallback: plan),
                        spaceID: customizationSpaceID,
                        previewSpace: flow.customizationPreviewSpace(
                            customizationSpaceID
                        ),
                        done: { self.customizationSpaceID = nil }
                    )
                } else {
                    BrowserOnboardingStepContent(
                        cloudSync: cloudSync,
                        progress: progress,
                        flow: flow,
                        selectedSourceSpaceID: $selectedSourceSpaceID,
                        selectedManualSpaceID: $selectedManualSpaceID,
                        customizationSpaceID: $customizationSpaceID,
                        close: close,
                        openCrest: openCrest
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 660)
        .preferredColorScheme(
            BrowserOnboardingAppearancePolicy.colorSchemeOverride(
                isManualSetup: flow.step == .manualSetup
            )
        )
        .tint(CrestBrandTheme.accent)
        .background(BrowserOnboardingWindowConfigurator())
        .task {
            await start()
        }
        .onChange(of: request) { _, newRequest in
            resetTransientState(for: newRequest)
        }
        .onChange(of: flow.state) { _, newState in
            synchronizePresentationState(for: newState)
        }
        .onDisappear(perform: flow.cancelOperations)
        .animation(motion(CrestMotion.onboardingStep), value: flow.state)
    }

    private func start() async {
        flow.discoverInstalledSources()
        if progress.isChecking {
            await progress.refresh()
        }
    }

    private func resetTransientState(for request: BrowserOnboardingRequest) {
        selectedSourceSpaceID = nil
        customizationSpaceID = nil
        withAnimation(motion(CrestMotion.onboardingStep)) {
            flow.reset(for: request)
        }
        selectedManualSpaceID = flow.manualPlan?.spaces.first?.id
    }

    private func synchronizePresentationState(
        for state: BrowserOnboardingFlowState
    ) {
        switch state {
        case .reviewing:
            if flow.plan?.spaces.contains(where: {
                $0.id == selectedSourceSpaceID
            }) != true {
                selectedSourceSpaceID = flow.plan?.spaces.first?.id
            }
        case .manualSetup:
            if flow.manualPlan?.spaces.contains(where: {
                $0.id == selectedManualSpaceID
            }) != true {
                selectedManualSpaceID = flow.manualPlan?.spaces.first?.id
            }
        case .welcome, .featureSpaces, .featureTabs, .featureSync,
            .importSelection, .reading, .committing, .complete:
            break
        }
    }

    private func planBinding(
        fallback: BrowserImportReviewPlan
    ) -> Binding<BrowserImportReviewPlan> {
        Binding(
            get: { flow.plan ?? fallback },
            set: { plan in
                flow.updatePlan(plan)
            }
        )
    }

    private func motion(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}

#Preview("Window Content") {
    @Previewable @State var selectedSourceSpaceID: SpaceID? = nil
    @Previewable @State var selectedManualSpaceID: SpaceID? = nil
    @Previewable @State var customizationSpaceID: SpaceID? = nil
    let fixture = BrowserOnboardingWindowPreviewFixture()

    BrowserOnboardingWindowContent(
        request: fixture.request,
        cloudSync: fixture.cloudSync,
        progress: fixture.progress,
        flow: fixture.flow,
        selectedSourceSpaceID: $selectedSourceSpaceID,
        selectedManualSpaceID: $selectedManualSpaceID,
        customizationSpaceID: $customizationSpaceID,
        close: {},
        openCrest: {}
    )
    .frame(width: 980, height: 660)
}
