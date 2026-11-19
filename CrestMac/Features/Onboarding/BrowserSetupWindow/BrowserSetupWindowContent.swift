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
    /// Whether setup finished and the preview grows to fill the window.
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
                    .padding(.leading, isTakingOver ? 0 : stepsWidth)
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
        // Crest opens on the guide once setup finishes, so the preview grows
        // into the window showing it too.
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
    /// preview takes over. What it holds keeps its own width as it slides, so
    /// nothing on it lays out again.
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
            startBrowsing: { startBrowsing(live.edits) },
            openCrest: openCrest,
            setUpWithoutCloud: cloudWait.setUpWithoutCloud
        )
        .frame(width: windowWidth, alignment: .leading)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background { BrowserSetupPaper() }
        .clipped()
        .shadow(
            color: CrestBrandPalette.ink.opacity(isLanding ? 0 : BrowserSetupWindowMetrics.sheetShadow),
            radius: BrowserSetupWindowMetrics.sheetShadowRadius, x: BrowserSetupWindowMetrics.sheetShadowOffset
        )
        .tint(CrestBrandTheme.accent)
        .opacity(isTakingOver ? 0 : 1)
    }

    /// The Crest window setup builds, as Crest itself draws it, at its real
    /// size in the room beside the steps.
    private var preview: some View {
        ZStack {
            BrowserSetupLiveWindow(
                session: live, cornerRadius: isTakingOver ? 0 : BrowserSetupLiveWindowMetrics.cornerRadius)
            if live.copy == nil, flow.isReading {
                ProgressView()
            }
        }
        .shadow(
            color: CrestBrandPalette.ink.opacity(isTakingOver ? 0 : BrowserSetupWindowMetrics.previewShadow),
            radius: 30, y: 18
        )
        .padding(isTakingOver ? EdgeInsets() : BrowserSetupWindowMetrics.previewInsets)
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
    static let previewShadow = 0.3
    /// The shadow the sheet's edge casts on the room.
    static let sheetShadow = 0.2
    static let sheetShadowRadius: CGFloat = 16
    static let sheetShadowOffset: CGFloat = 4

    static func panelWidth(in windowWidth: CGFloat) -> CGFloat {
        min(max(windowWidth / 3, panelWidths.lowerBound), panelWidths.upperBound)
    }
}
