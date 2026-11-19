import SwiftUI

/// Setup on iPhone and iPad. The core holds the step, the manual setup, and
/// what finishing does. The welcome, the look and the manual setup are one
/// screen of steps beside a live preview; the tour of Crest's features and
/// bringing tabs in on a Mac have pages of their own.
struct MobileBrowserOnboardingView: View {
    let request: BrowserOnboardingRequest
    let browser: BrowserStore
    @Bindable var cloudSync: BrowserCloudSyncController
    @Bindable var progress: BrowserOnboardingProgressStore
    @Bindable var coordinator: BrowserOnboardingCoordinator
    let tutorialPersonalSpace: SpaceModel
    let tutorialWorkSpace: SpaceModel
    let spaceAccess: BrowserSpaceAccessController
    let didOpenGettingStarted: (BrowserTabRuntimeAssignment) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The manual setup the core holds, which it keeps for the next launch
    /// until setup finishes.
    @State private var setup: BrowserManualSetupModel
    /// How long the welcome has waited on iCloud's check.
    @State private var cloudWait = BrowserOnboardingCloudWait()
    @State private var errorMessage: String?
    @State private var completionTask: Task<Void, Never>?
    /// The step shown while finishing, which stays as the sheet goes.
    @State private var finishingStep: SetupStep?
    /// Whether setup finished and its copy of Crest grows to fill the screen
    /// before Crest shows in its place.
    @State private var isTakingOver = false
    /// What the person changed in the preview's tabs and folders, which
    /// Crest takes once setup finishes.
    @State private var carriedEdits: BrowserSetupCopyEdits?

    init(
        request: BrowserOnboardingRequest,
        browser: BrowserStore,
        cloudSync: BrowserCloudSyncController,
        progress: BrowserOnboardingProgressStore,
        coordinator: BrowserOnboardingCoordinator,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        didOpenGettingStarted: @escaping (BrowserTabRuntimeAssignment) -> Void = { _ in },
        tutorialPersonalSpace: SpaceModel =
            MobileOnboardingPreviewFixtures.tutorialPersonalSpace,
        tutorialWorkSpace: SpaceModel =
            MobileOnboardingPreviewFixtures.tutorialWorkSpace
    ) {
        self.request = request
        self.browser = browser
        self.cloudSync = cloudSync
        self.progress = progress
        self.coordinator = coordinator
        self.didOpenGettingStarted = didOpenGettingStarted
        self.spaceAccess = spaceAccess
        self.tutorialPersonalSpace = tutorialPersonalSpace
        self.tutorialWorkSpace = tutorialWorkSpace
        _setup = State(initialValue: BrowserManualSetupModel(core: browser.core))
    }

    /// Setup as the core holds it, or nil before it opens.
    private var flow: SetupFlowState? { browser.core.state.setupFlow }

    private var step: SetupStep { finishingStep ?? flow?.step ?? request.entryPoint.firstStep }

    var body: some View {
        ZStack {
            // Clear as setup hands over, so Crest shows through as the steps
            // slide away.
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
                .opacity(isTakingOver ? 0 : 1)

            if showsSetup {
                setupView
            } else {
                MobileOnboardingCurrentPage(context: pageContext)
                    .transition(.opacity)
            }
        }
        .crestFieldSurfaceRole(.brand)
        .modifier(lifecycleModifier)
        .task { await cloudWait.run() }
        .disabled(completionTask != nil)
        .onDisappear { completionTask?.cancel() }
    }

    /// Whether the step is one the setup screen draws: the welcome, the look
    /// and the manual setup, which it shows as one screen of steps beside a
    /// live preview.
    private var showsSetup: Bool {
        step == .welcome || step == .look || step == .manualSetup
    }

    private var setupView: some View {
        MobileSetupView(
            browser: browser, setup: setup, welcome: welcomeAction,
            firstPath: request.entryPoint.firstStep == .manualSetup ? [.spaces] : [],
            closes: !request.entryPoint.isGuided, errorMessage: errorMessage,
            isFinishing: completionTask != nil || coordinator.isHandingOver,
            isTakingOver: isTakingOver, setUpWithoutCloud: cloudWait.setUpWithoutCloud,
            startBrowsing: startBrowsing,
            prepareCrest: { coordinator.preparesBrowser = true },
            openCrest: completeSetup, close: close)
    }

    private var lifecycleModifier: MobileOnboardingLifecycleModifier {
        MobileOnboardingLifecycleModifier(
            request: request,
            appeared: { start(request) },
            requestChanged: reset
        )
    }

    private var pageContext: MobileOnboardingPageContext {
        MobileOnboardingPageContext(
            step: step,
            previewWidth: previewWidth,
            personalSpace: tutorialPersonalSpace,
            workSpace: tutorialWorkSpace,
            featureCloseTitle: featureCloseTitle,
            featureCloseAction: featureCloseAction,
            advance: advance,
            close: close,
            reviewFeatures: { move(to: .featureSpaces) }
        )
    }

    private var welcomeAction: BrowserOnboardingWelcomeAction {
        BrowserOnboardingWelcomeAction(
            flow: flow, cloudPhase: cloudSync.phase, wait: cloudWait.stage, forcesSetup: progress.forcesSetup)
    }

    private var featureCloseTitle: String? {
        request.entryPoint == .firstRun ? nil : "Close"
    }

    private var featureCloseAction: (() -> Void)? {
        guard request.entryPoint != .firstRun else { return nil }
        return { close() }
    }

    private var previewWidth: CGFloat {
        horizontalSizeClass == .regular
            ? MobileOnboardingLayout.regularPreviewWidth
            : MobileOnboardingLayout.compactPreviewWidth
    }

    /// Finishes setup with the manual setup applied, then makes `edits`,
    /// what the person changed in the preview's tabs and folders, in Crest.
    private func startBrowsing(_ edits: BrowserSetupCopyEdits?) {
        if step != .manualSetup { move(to: .manualSetup) }
        carriedEdits = edits
        completeSetup()
    }

    /// Goes on to the step the core says follows this one.
    private func advance() {
        guard let next = flow?.nextStep else { return }
        move(to: next)
    }

    private func move(to newStep: SetupStep) {
        withAnimation(
            CrestMotion.selection.unlessReducingMotion(reduceMotion)
        ) {
            _ = try? browser.core.send(ShowSetupStep(step: newStep))
        }
    }

    private func reset(for request: BrowserOnboardingRequest) {
        completionTask?.cancel()
        completionTask = nil
        errorMessage = nil
        start(request)
    }

    /// Opens setup in the core for `request`. The core goes on with the
    /// manual setup it kept, following Spaces changed meanwhile; a rerun
    /// starts it over.
    private func start(_ request: BrowserOnboardingRequest) {
        finishingStep = nil
        isTakingOver = false
        _ = try? browser.core.send(StartSetup(workspaceID: browser.family.workspaceID, entry: request.entryPoint))
        if request.entryPoint.firstStep != .importBrowser, setup.draft == nil {
            _ = try? browser.core.send(ShowSetupStep(step: .manualSetup))
        }
    }

    /// Finishes setup: the core applies the manual setup and completes setup
    /// on this device, and the guide opens where the core names it. Setup
    /// shows it is finishing at once, a frame before the work begins, and
    /// Crest comes up behind it if it has not already.
    private func completeSetup() {
        guard completionTask == nil else { return }
        finishingStep = step
        completionTask = Task { @MainActor in
            try? await Task.sleep(for: MobileBrowserOnboardingMetrics.feedbackFrame)
            coordinator.preparesBrowser = true
            let result = await BrowserSetupFinish.finish(browser: browser, spaceAccess: spaceAccess)
            guard !Task.isCancelled else { return }
            completionTask = nil
            result.apply(to: self)
        }
    }

    private func close() {
        coordinator.finishMobilePresentation()
    }
}

extension MobileBrowserOnboardingView: BrowserSetupFinishReceiver {
    // MARK: - Actions - Finishing

    func setupCompleted(guide: BrowserTabRuntimeAssignment?) {
        errorMessage = nil
        carriedEdits?.replay(into: browser)
        carriedEdits = nil
        // Crest shows the page it opens on behind setup, which waits for it,
        // so setup goes over a finished page rather than one still coming up.
        coordinator.isHandingOver = true
        if let guide { didOpenGettingStarted(guide) }
        guard showsSetup, !reduceMotion else {
            finishPresentation()
            return
        }
        // A phone's page covers the screen, rising over setup as it comes.
        let pageRises = guide != nil && horizontalSizeClass == .compact
        Task { @MainActor in
            // These end once the main thread has built and drawn the page.
            for _ in 0..<MobileBrowserOnboardingMetrics.handOverFrames {
                try? await Task.sleep(for: MobileBrowserOnboardingMetrics.feedbackFrame)
            }
            if pageRises {
                // Setup goes once the page has risen over it.
                try? await Task.sleep(for: MobileBrowserOnboardingMetrics.pageRise)
            } else {
                // An iPad's copy of Crest grows to fill the screen, and steps
                // standing alone slide away over Crest; setup then goes.
                withAnimation(CrestMotion.onboardingHandOver) { isTakingOver = true }
                try? await Task.sleep(for: .seconds(CrestMotion.onboardingHandOverTransition))
            }
            finishPresentation()
        }
    }

    /// Marks setup finished on this device and lets Crest show.
    private func finishPresentation() {
        progress.setupFinished()
        // Handing over, setup goes in the frame Crest takes its place.
        var transaction = Transaction()
        transaction.disablesAnimations = coordinator.isHandingOver
        withTransaction(transaction) { coordinator.finishMobilePresentation() }
    }

    func setupCancelled() {
        finishingStep = nil
        errorMessage = String(localized: "Unlock your first Space to open Getting Started.")
    }

    func setupRefused(_ message: String) {
        finishingStep = nil
        errorMessage = message
    }
}

#Preview("Mobile Onboarding — Root") {
    let fixture = MobileBrowserPreviewFixture()
    let progress = BrowserOnboardingProgressStore(
        core: fixture.browser.core, environment: BrowserLaunchEnvironment.current.coreEnvironment)
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
        tutorialPersonalSpace: fixture.alternateSpace,
        tutorialWorkSpace: fixture.space
    )
}

enum MobileBrowserOnboardingMetrics {
    /// About one frame: the wait for setup to show it is finishing before
    /// the work begins, and each wait for Crest to draw behind setup.
    static let feedbackFrame = Duration.milliseconds(20)
    /// The frames setup waits, once Crest builds its page, before it goes.
    static let handOverFrames = 3
    /// How long a phone's page takes to rise over setup, which goes after.
    static let pageRise = Duration.milliseconds(650)
}
