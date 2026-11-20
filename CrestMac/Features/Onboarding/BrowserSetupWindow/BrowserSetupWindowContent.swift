import SwiftUI

/// Setup as one window and a sheet of Crest's paper: the welcome fills the
/// window as Crest's website opens, so the way in is the one thing to do.
/// Continue slides the sheet to a third of the window, the steps on it in
/// turn, and beside it comes the Crest window setup builds, Crest's own
/// browser over a live copy of what setup would leave, which every choice
/// changes and which the person can use, in a room of paper in the colors
/// of the look it shows.
struct BrowserSetupWindowContent: View {
    // MARK: - Variables

    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let flow: BrowserOnboardingFlow
    let cloudWait: BrowserOnboardingCloudWait
    /// Whether setup finished and hands over to the Crest window drawn behind
    /// it: the preview moves into that window's place as setup fades into it.
    let isTakingOver: Bool
    let close: () -> Void
    /// Finishes setup, carrying what the person changed in the copy's tabs
    /// and folders into Crest.
    let startBrowsing: (BrowserSetupCopyEdits?) -> Void
    let openCrest: () -> Void

    @State private var path: [BrowserSetupDestination] = []
    @State private var shownSpaceID: UUID?
    @State private var live = BrowserSetupLiveSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the welcome fills the window, before the steps or the
    /// take-over.
    private var isLanding: Bool {
        path.isEmpty && !isTakingOver
    }

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            let stepsWidth = BrowserSetupWindowMetrics.panelWidth(in: geometry.size.width)
            ZStack(alignment: .leading) {
                preview
                    .padding(.leading, stepsWidth)
                    // Into the place of the window Crest opens behind setup,
                    // as setup fades into it.
                    .offset(
                        x: isTakingOver ? -(stepsWidth + BrowserSetupWindowMetrics.previewInsets.leading) : 0,
                        y: isTakingOver ? -BrowserSetupWindowMetrics.previewInsets.top : 0
                    )
                    .opacity(isLanding ? 0 : 1)
                    // Off the trailing edge on the welcome, it comes in with
                    // the sheet's edge, so the two never overlap.
                    .offset(x: isLanding ? geometry.size.width - stepsWidth : 0)
                    .allowsHitTesting(!isLanding)
                    .accessibilityHidden(isLanding)
                sheet(stepsWidth: stepsWidth, windowWidth: geometry.size.width)
            }
            .background {
                BrowserSetupPaperRoom(look: live.shownLook)
            }
            .animation(CrestMotion.onboardingSheet.unlessReducingMotion(reduceMotion), value: isLanding)
        }
        .frame(minWidth: 1120, minHeight: 720)
        .ignoresSafeArea()
        .background(BrowserOnboardingWindowConfigurator())
        .task { await start() }
        .task { await cloudWait.run() }
        .onChange(of: request) { _, request in
            flow.reset(for: request)
            path = Self.firstPath(for: request)
            flow.beginLiveSetup()
        }
        .onChange(of: flow.firstIncomingPreviewSpaceID) { _, spaceID in
            if let spaceID { shownSpaceID = spaceID }
        }
        .onChange(of: flow.setupSession, initial: true) { _, session in
            guard let session else { return }
            live.show(session.seed, images: session.images, spaceID: shownSpaceID)
        }
        .onChange(of: shownSpaceID) { _, spaceID in live.show(spaceID) }
        // Crest opens on the guide once setup finishes, so the preview shows
        // it too as setup fades into Crest.
        .onChange(of: isTakingOver) { _, isTakingOver in
            if isTakingOver { live.showGettingStarted() }
        }
        .onDisappear {
            flow.cancelOperations()
            live.close()
        }
    }

    /// The sheet of paper setup lies on: the whole window on the welcome, a
    /// third of it for the steps, attached to the window's leading edge,
    /// its trailing edge casting a shadow on the room; it slides away as the
    /// preview takes over. What it holds, and the paper itself, keep the
    /// window's width as it slides, and only how much of them shows changes,
    /// so nothing on it lays out or draws again on the way.
    private func sheet(stepsWidth: CGFloat, windowWidth: CGFloat) -> some View {
        let width = isTakingOver ? 0 : isLanding ? windowWidth : stepsWidth
        return BrowserSetupStepsPanel(
            flow: flow,
            stepsWidth: stepsWidth,
            welcome: welcome,
            closes: !request.entryPoint.isGuided,
            path: $path,
            shownSpaceID: $shownSpaceID,
            close: close,
            startBrowsing: {
                let edits = live.edits
                live.showGettingStarted()
                startBrowsing(edits)
            },
            openCrest: {
                live.showGettingStarted()
                openCrest()
            },
            setUpWithoutCloud: cloudWait.setUpWithoutCloud
        )
        .frame(width: windowWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background { BrowserSetupPaper() }
        .frame(width: width, alignment: .leading)
        .clipped()
        .overlay(alignment: .trailing) {
            BrowserSetupSheetEdge()
                .opacity(isLanding ? 0 : 1)
        }
        .tint(CrestBrandTheme.accent)
        .opacity(isTakingOver ? 0 : 1)
    }

    /// The Crest window setup builds, as Crest itself draws it, at its real
    /// size in the room beside the steps.
    private var preview: some View {
        ZStack {
            BrowserSetupLiveWindow(session: live)
            if live.copy == nil, flow.isReading {
                ProgressView()
            }
        }
        .padding(BrowserSetupWindowMetrics.previewInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What the welcome offers as iCloud answers.
    private var welcome: BrowserOnboardingWelcomeAction {
        BrowserOnboardingWelcomeAction(
            flow: flow.state, cloudPhase: cloudSync.phase, wait: cloudWait.stage, forcesSetup: progress.forcesSetup)
    }

    // MARK: - Actions - Starting

    private func start() async {
        path = Self.firstPath(for: request)
        flow.start()
        flow.discoverInstalledSources()
        flow.beginLiveSetup()
    }

    /// The page setup opens on for `request`: the list of steps, or the step
    /// the person came for.
    private static func firstPath(for request: BrowserOnboardingRequest) -> [BrowserSetupDestination] {
        switch request.entryPoint.firstStep.kind {
        case .importBrowser: [.bring]
        case .manualSetup: [.spaces]
        default: []
        }
    }
}

enum BrowserSetupWindowMetrics {
    /// The steps take about a third of the window, within these widths.
    static let panelWidths: ClosedRange<CGFloat> = 380...440
    /// The room around the preview.
    static let previewInsets = EdgeInsets(top: 44, leading: 44, bottom: 44, trailing: 44)

    static func panelWidth(in windowWidth: CGFloat) -> CGFloat {
        min(max(windowWidth / 3, panelWidths.lowerBound), panelWidths.upperBound)
    }
}
