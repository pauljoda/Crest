import SwiftUI

struct BrowserOnboardingStepContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let flow: BrowserOnboardingFlow
    @Binding var selectedSourceSpaceID: SpaceID?
    @Binding var selectedManualSpaceID: SpaceID?
    @Binding var customizationSpaceID: SpaceID?
    let close: () -> Void
    let openCrest: () -> Void

    var body: some View {
        switch flow.step {
        case .welcome:
            BrowserOnboardingWelcomePage(
                progressIsChecking: progress.isChecking,
                cloudPhase: cloudSync.phase,
                hasCompletedSetup: progress.hasCompletedSetup,
                hasDisposableSeedState:
                    flow.browser.session.hasDisposableSeedState,
                continueSetup: { transition(to: .featureSpaces) },
                openCrest: openCrest
            )
        case .featureSpaces:
            tutorialPage(.spaces, back: .welcome, next: .featureTabs)
        case .featureTabs:
            tutorialPage(.tabs, back: .featureSpaces, next: .featureSync)
        case .featureSync:
            tutorialPage(
                .sync,
                back: .featureTabs,
                next: flow.nextImportStep
            )
        case .importBrowser:
            BrowserOnboardingImportPage(
                entryPoint: flow.request.entryPoint,
                sources: flow.installedSources,
                selectedApplications: flow.selectedImportApplications,
                isReading: flow.isReading,
                isLocked: flow.isImportSelectionLocked,
                failure: flow.failure?.message,
                accessLabel: flow.importAccessLabel,
                toggleSelection: flow.toggleImportSelection,
                beginManualSetup: beginManualSetup,
                continueImport: flow.continueImportQueue,
                back: { transition(to: .featureSync) },
                close: close
            )
        case .review:
            BrowserOnboardingReviewPage(
                flow: flow,
                browserSession: flow.browser.session,
                application: flow.selectedApplication,
                sources: flow.installedSources,
                selectedSourceSpaceID: $selectedSourceSpaceID,
                customizationSpaceID: $customizationSpaceID,
                back: { transition(to: .importBrowser) }
            )
        case .manualSetup:
            BrowserOnboardingManualSetupPage(
                flow: flow,
                browserSession: flow.browser.session,
                selectedSpaceID: $selectedManualSpaceID,
                back: { transition(to: .importBrowser) }
            )
        case .complete:
            BrowserOnboardingCompletionPage(
                summary: flow.completionSummary,
                openCrest: openCrest
            )
        }
    }

    private func tutorialPage(
        _ tutorial: BrowserMacOnboardingTutorial,
        back: BrowserOnboardingStep,
        next: BrowserOnboardingStep
    ) -> some View {
        BrowserMacOnboardingTutorialPage(
            tutorial: tutorial,
            back: { transition(to: back) },
            next: { transition(to: next) }
        )
    }

    private func beginManualSetup() {
        flow.beginManualSetup()
        if flow.manualPlan?.spaces.contains(where: {
            $0.id == selectedManualSpaceID
        }) != true {
            selectedManualSpaceID = flow.manualPlan?.spaces.first?.id
        }
    }

    private func transition(to step: BrowserOnboardingStep) {
        withAnimation(motion(CrestMotion.onboardingStep)) {
            flow.show(step)
        }
    }

    private func motion(_ animation: Animation) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}

#Preview("Welcome Step") {
    @Previewable @State var selectedSourceSpaceID: SpaceID? = nil
    @Previewable @State var selectedManualSpaceID: SpaceID? = nil
    @Previewable @State var customizationSpaceID: SpaceID? = nil
    let fixture = BrowserOnboardingWindowPreviewFixture()

    BrowserOnboardingStepContent(
        cloudSync: fixture.cloudSync,
        progress: fixture.progress,
        flow: fixture.flow,
        selectedSourceSpaceID: $selectedSourceSpaceID,
        selectedManualSpaceID: $selectedManualSpaceID,
        customizationSpaceID: $customizationSpaceID,
        close: {},
        openCrest: {}
    )
    .frame(width: 980, height: 604)
}
