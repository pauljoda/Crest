import SwiftUI

/// Setup as one window, a room lit by the look it shows: the steps on a
/// frosted panel on the left, the welcome and then each step in turn, and on
/// the right the Crest window setup builds, Crest's own browser over a live
/// copy of what setup would leave, which every choice changes and which the
/// person can use. While the welcome shows, the window idles through looks.
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
    /// The glass's scheme once a look has settled it.
    @State private var heldScheme: ColorScheme?

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                panel(width: BrowserSetupWindowMetrics.panelWidth(in: geometry.size.width))
                preview
            }
            .background {
                BrowserSetupAmbientBackdrop(look: live.shownLook, isIdling: idles)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .ignoresSafeArea()
        .background(BrowserOnboardingWindowConfigurator())
        .task { await start() }
        .task { await cloudWait.run() }
        .task(id: idles) { await idle() }
        .task(id: BrowserSetupRoomSchemeKey(scheme: lookScheme, hasLook: live.shownLook != nil)) {
            await settleRoomScheme()
        }
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
        .onDisappear {
            flow.cancelOperations()
            live.close()
        }
    }

    /// The steps on a frosted panel floating in the room, light or dark as
    /// the room is, which slides away as the preview takes over.
    private func panel(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrowserSetupWindowMetrics.panelRadius, style: .continuous)
        return BrowserSetupStepsPanel(
            flow: flow,
            welcome: welcome,
            closes: !request.entryPoint.isGuided,
            path: $path,
            shownSpaceID: $shownSpaceID,
            close: close,
            startBrowsing: { startBrowsing(live.edits) },
            openCrest: openCrest,
            setUpWithoutCloud: cloudWait.setUpWithoutCloud
        )
        .frame(width: width)
        .padding(.top, BrowserSetupWindowMetrics.panelTop)
        .background { BrowserSetupGlassPane(shape: shape, scheme: roomScheme) }
        .clipShape(shape)
        .overlay { BrowserSetupGlassEdge(shape: shape, scheme: roomScheme) }
        .shadow(color: .black.opacity(BrowserSetupWindowMetrics.panelContactShadow), radius: 1.5, y: 1)
        .shadow(color: .black.opacity(BrowserSetupWindowMetrics.panelShadow), radius: 34, y: 20)
        .environment(\.crestControlAccent, .primary)
        .environment(\.colorScheme, roomScheme)
        .animation(
            idles ? CrestMotion.onboardingBackdrop : CrestMotion.onboardingBackdropChange, value: roomScheme
        )
        .padding(BrowserSetupWindowMetrics.panelInset)
        // Unclipped, so the panel's shadow falls on the room unbroken; it
        // fades away as its room closes for the take-over.
        .frame(width: isTakingOver ? 0 : nil, alignment: .trailing)
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
        .shadow(color: .black.opacity(isTakingOver ? 0 : BrowserSetupWindowMetrics.previewShadow), radius: 40, y: 24)
        .padding(isTakingOver ? 0 : BrowserSetupWindowMetrics.previewInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Light glass over a light room and dark glass over a dark one, as
    /// the look the room shows reads now; `roomScheme` follows it once it
    /// holds.
    private var lookScheme: ColorScheme {
        guard let look = live.shownLook else { return .dark }
        return look.foregroundTone(over: .dark) == .light ? .dark : .light
    }

    /// Light glass over a light room and dark glass over a dark one: the
    /// scheme a look settled, or the first look's own.
    private var roomScheme: ColorScheme {
        heldScheme ?? lookScheme
    }

    /// Turns the glass to `lookScheme` once it has held a moment, so a color
    /// dragged back and forth across the turn between light and dark turns
    /// the panel once, as it settles, rather than at every crossing.
    private func settleRoomScheme() async {
        guard let held = heldScheme else {
            if live.shownLook != nil { heldScheme = lookScheme }
            return
        }
        guard held != lookScheme else { return }
        try? await Task.sleep(for: BrowserSetupWindowMetrics.roomSchemeHold)
        guard !Task.isCancelled else { return }
        heldScheme = lookScheme
    }

    // MARK: - Actions - Idling

    /// Whether the window idles through looks: while the welcome shows,
    /// before the take-over, unless iCloud brought Spaces, which the preview
    /// shows as they are.
    private var idles: Bool {
        path.isEmpty && !isTakingOver && live.copy != nil && !welcome.opensCrest
    }

    /// What the welcome offers as iCloud answers.
    private var welcome: BrowserOnboardingWelcomeAction {
        BrowserOnboardingWelcomeAction(
            flow: flow.state, cloudPhase: cloudSync.phase, wait: cloudWait.stage, forcesSetup: progress.forcesSetup)
    }

    /// Dresses the window in one look after another while it idles, and puts
    /// setup's own looks back once it stops.
    private func idle() async {
        guard idles else {
            live.settle()
            return
        }
        guard let base = live.shownLook else { return }
        // Light looks, then dark ones, so the text and materials turn between
        // light and dark twice a round rather than at every change.
        let dressed = BrowserSetupIdleLooks.all.map { $0.wearing(on: base) }
        let looks =
            dressed.filter { $0.foregroundTone(over: .dark) == .dark }
            + dressed.filter { $0.foregroundTone(over: .dark) != .dark }
        var index = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: BrowserSetupWindowMetrics.idleInterval)
            guard !Task.isCancelled else { return }
            live.idle(in: looks[index % looks.count])
            index += 1
        }
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

/// What the glass's scheme settles from: the scheme the shown look reads in,
/// and whether a look shows yet.
private struct BrowserSetupRoomSchemeKey: Hashable {
    let scheme: ColorScheme
    let hasLook: Bool
}

enum BrowserSetupWindowMetrics {
    /// The steps take about a third of the window, within these widths.
    static let panelWidths: ClosedRange<CGFloat> = 360...420
    static let previewInset: CGFloat = 28
    /// The panel floats this far in from the window's edges, below the
    /// window buttons, with this much room above its own header.
    static let panelInset: CGFloat = 28
    static let panelTop: CGFloat = 10
    static let panelRadius: CGFloat = 22
    static let panelContactShadow = 0.18
    static let panelShadow = 0.26
    static let previewShadow = 0.38
    /// How long a look must hold before the glass turns between light and
    /// dark.
    static let roomSchemeHold = Duration.milliseconds(250)
    /// How long the welcome shows each look.
    static let idleInterval = Duration.seconds(6)

    static func panelWidth(in windowWidth: CGFloat) -> CGFloat {
        min(max(windowWidth / 3, panelWidths.lowerBound), panelWidths.upperBound)
    }
}
