import SwiftUI

struct MobileBrowserOnboardingView: View {
    let request: BrowserOnboardingRequest
    let browser: BrowserStore
    @Bindable var cloudSync: BrowserCloudSyncController
    @Bindable var progress: BrowserOnboardingProgressStore
    @Bindable var coordinator: BrowserOnboardingCoordinator
    let draftPersistence: MobileOnboardingDraftPersistence
    let tutorialPersonalSpace: BrowserSpace
    let tutorialWorkSpace: BrowserSpace
    let spaceAccess: BrowserSpaceAccessController
    let didOpenGettingStarted: (BrowserTabRuntimeAssignment) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var step: MobileBrowserOnboardingStep
    @State private var manualPlan: BrowserManualSetupPlan
    @State private var selectedSpaceID: SpaceID?
    @State private var customizedSpaceID: SpaceID?
    @State private var errorMessage: String?
    @State private var completionTask: Task<Void, Never>?

    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        coordinator: BrowserOnboardingCoordinator,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        didOpenGettingStarted: @escaping (BrowserTabRuntimeAssignment) -> Void = { _ in },
        draftPersistence: MobileOnboardingDraftPersistence = .live,
        tutorialPersonalSpace: BrowserSpace =
            MobileOnboardingPreviewFixtures.tutorialPersonalSpace,
        tutorialWorkSpace: BrowserSpace =
            MobileOnboardingPreviewFixtures.tutorialWorkSpace
    ) {
        self.request = request
        self.browser = browser
        self.cloudSync = cloudSync
        self.progress = progress
        self.coordinator = coordinator
        self.didOpenGettingStarted = didOpenGettingStarted
        self.spaceAccess = spaceAccess
        self.draftPersistence = draftPersistence
        self.tutorialPersonalSpace = tutorialPersonalSpace
        self.tutorialWorkSpace = tutorialWorkSpace

        let resumedPlan = draftPersistence.plan(for: request, existing: browser.session)

        _manualPlan = State(initialValue: resumedPlan)
        _selectedSpaceID = State(initialValue: resumedPlan.spaces.first?.id)
        _step = State(
            initialValue: MobileBrowserOnboardingPolicy.initialStep(for: request)
        )
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            MobileOnboardingCurrentPage(context: pageContext)
                .transition(.opacity)
        }
        .tint(.accentColor)
        .modifier(lifecycleModifier)
        .disabled(completionTask != nil)
        .onDisappear { completionTask?.cancel() }
    }

    private var lifecycleModifier: MobileOnboardingLifecycleModifier {
        MobileOnboardingLifecycleModifier(
            request: request,
            progress: progress,
            plan: $manualPlan,
            customizedSpaceID: $customizedSpaceID,
            draftPersistence: draftPersistence,
            browser: browser,
            requestChanged: reset
        )
    }

    private var pageContext: MobileOnboardingPageContext {
        MobileOnboardingPageContext(
            step: step,
            welcomeAction: welcomeAction,
            welcomePrimaryTitle: welcomePrimaryTitle,
            welcomeStatus: welcomeStatus(welcomeAction),
            previewWidth: previewWidth,
            personalSpace: tutorialPersonalSpace,
            workSpace: tutorialWorkSpace,
            featureCloseTitle: featureCloseTitle,
            featureCloseAction: featureCloseAction,
            plan: $manualPlan,
            selectedSpaceID: $selectedSpaceID,
            existingSession: browser.session,
            horizontalSizeClass: horizontalSizeClass,
            errorMessage: errorMessage,
            opensGettingStarted: progress.willOpenGettingStarted(for: request.entryPoint),
            setupSecondaryTitle: setupSecondaryTitle,
            welcomePrimaryAction: handleWelcomeAction,
            advance: advance,
            setupSecondaryAction: handleSetupSecondaryAction,
            finish: finishManualSetup,
            addSpace: addSpace,
            customize: { customizedSpaceID = $0 },
            remove: removeSpace,
            close: close,
            reviewFeatures: { move(to: .featureSpaces) }
        )
    }

    private var welcomeAction: BrowserOnboardingWelcomeAction {
        BrowserOnboardingWelcomePolicy.action(
            progressIsChecking: progress.isChecking,
            cloudPhase: cloudSync.phase,
            hasCompletedSetup: progress.hasCompletedSetup,
            entryPoint: request.entryPoint
        )
    }

    private var welcomePrimaryTitle: String {
        switch welcomeAction {
        case .checking:
            "Checking iCloud"
        case .setup:
            "Get Started"
        case .open:
            "Open Crest"
        }
    }

    private var featureCloseTitle: String? {
        request.entryPoint == .firstRun ? nil : "Close"
    }

    private var featureCloseAction: (() -> Void)? {
        guard request.entryPoint != .firstRun else { return nil }
        return { close() }
    }

    private var setupSecondaryTitle: String {
        request.entryPoint.isGuidedSetup ? "Back" : "Cancel"
    }

    private var previewWidth: CGFloat {
        horizontalSizeClass == .regular
            ? MobileOnboardingLayout.regularPreviewWidth
            : MobileOnboardingLayout.compactPreviewWidth
    }

    private func handleWelcomeAction() {
        switch welcomeAction {
        case .checking:
            return
        case .setup:
            advance()
        case .open:
            completeSetup()
        }
    }

    private func advance() {
        guard let next = MobileBrowserOnboardingPolicy.nextStep(after: step) else {
            return
        }
        move(to: next)
    }

    private func handleSetupSecondaryAction() {
        if request.entryPoint.isGuidedSetup {
            move(to: .welcome)
        } else {
            close()
        }
    }

    private func move(to newStep: MobileBrowserOnboardingStep) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.selection,
                    reduceMotion: reduceMotion
                )
            ) {
                step = newStep
            }
        }
    }

    private func addSpace() {
        do {
            let newSpaceID = try manualPlan.addSpace()
            errorMessage = nil
            if reduceMotion {
                selectedSpaceID = newSpaceID
            } else {
                withAnimation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.onboardingProgress,
                        reduceMotion: reduceMotion
                    )
                ) {
                    selectedSpaceID = newSpaceID
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeSpace(_ spaceID: SpaceID) {
        let index = manualPlan.spaces.firstIndex { $0.id == spaceID }
        guard manualPlan.removeSpace(spaceID) else { return }
        let fallbackIndex = min(index ?? 0, max(0, manualPlan.spaces.count - 1))
        selectedSpaceID =
            manualPlan.spaces[
                mobileOnboardingSafe: fallbackIndex
            ]?.id
        errorMessage = nil
    }

    private func welcomeStatus(_ action: BrowserOnboardingWelcomeAction) -> String {
        if action == .checking {
            return "Checking iCloud for an existing Crest setup…"
        }
        if action == .open {
            return "Your existing Spaces are ready."
        }
        if !browser.session.hasDisposableSeedState {
            return "Your existing Spaces are ready to customize."
        }
        if case .failed = cloudSync.phase {
            return "iCloud is unavailable right now; you can still set up this device."
        }
        return "No existing setup was found in iCloud."
    }

    private func reset(for request: BrowserOnboardingRequest) {
        completionTask?.cancel()
        completionTask = nil
        customizedSpaceID = nil
        errorMessage = nil
        manualPlan = draftPersistence.plan(for: request, existing: browser.session)
        selectedSpaceID = manualPlan.spaces.first?.id
        move(to: MobileBrowserOnboardingPolicy.initialStep(for: request))
    }

    private func finishManualSetup() {
        do {
            _ = try manualPlan.preview(in: browser)
            completeSetup(manualPlan: manualPlan)
        } catch {
            errorMessage = error.personFacingDescription
        }
    }

    private func completeSetup(manualPlan: BrowserManualSetupPlan? = nil) {
        guard completionTask == nil else { return }
        completionTask = Task { @MainActor in
            let result = await BrowserOnboardingCompletion.complete(
                request: request, browser: browser, progress: progress, spaceAccess: spaceAccess,
                manualPlan: manualPlan,
                willComplete: { guide in
                    if let guide { didOpenGettingStarted(guide) }
                    draftPersistence.clear()
                    coordinator.isMobilePresented = false
                })
            guard !Task.isCancelled else { return }
            completionTask = nil
            switch result {
            case .completed:
                errorMessage = nil
            case .cancelled:
                errorMessage = "Unlock your first Space to open Getting Started."
            case .sourceChanged:
                errorMessage = "Your Spaces changed. Review setup and try again."
            }
        }
    }

    private func close() {
        coordinator.isMobilePresented = false
    }
}

#Preview("Mobile Onboarding — Root") {
    let fixture = MobileBrowserPreviewFixture()
    let progress = BrowserOnboardingProgressStore(
        persistence: InMemoryBrowserOnboardingProgressPersistence(),
        forceWelcome: true
    )
    MobileBrowserOnboardingView(
        request: BrowserOnboardingRequest(
            entryPoint: .firstRun,
            presentationID: UUID(
                uuid: (
                    0x34, 0xC8, 0x5B, 0x68, 0x41, 0xE4, 0x4A, 0x3C,
                    0xA4, 0xB9, 0x3F, 0x39, 0x72, 0x13, 0x3C, 0x42
                )
            )
        ),
        browser: fixture.browser,
        cloudSync: fixture.cloudSync,
        progress: progress,
        coordinator: fixture.onboardingCoordinator,
        draftPersistence: .preview,
        tutorialPersonalSpace: fixture.alternateSpace,
        tutorialWorkSpace: fixture.space
    )
}
