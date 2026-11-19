import SwiftUI

/// Setup on an iPad held wide, as on a Mac, on a sheet of Crest's paper: the
/// welcome fills the screen, so the way in is the one thing to do. Continue
/// slides the sheet to a third of the screen, the steps on it in turn, and
/// beside it comes Crest itself over a live copy of what setup builds, which
/// every choice changes and which the person can use, in a room of paper in
/// the colors of the look it shows. When setup finishes, the copy grows to
/// fill the screen before Crest shows.
struct MobilePadSetup: View {
    // MARK: - Variables

    let browser: BrowserStore
    let setup: BrowserManualSetupModel
    let welcome: BrowserOnboardingWelcomeAction
    /// Whether setup was opened for one step, so the welcome offers Cancel.
    let closes: Bool
    let errorMessage: String?
    /// Whether setup is finishing, which holds every action.
    let isFinishing: Bool
    /// Whether setup finished and the copy grows to fill the screen.
    let isTakingOver: Bool
    /// The live copy beside the steps, which setup keeps across a turn of
    /// the device.
    let live: MobileSetupLiveSession
    @Binding var path: [BrowserSetupDestination]
    @Binding var shownSpaceID: UUID?
    let setUpWithoutCloud: () -> Void
    /// Finishes setup, carrying what the person changed in the copy's tabs
    /// and folders into Crest.
    let startBrowsing: (BrowserSetupCopyEdits?) -> Void
    /// Brings Crest up behind setup, ready for when setup hands over to it.
    let prepareCrest: () -> Void
    let openCrest: () -> Void
    let close: () -> Void

    @State private var draftPreview = BrowserSetupDraftPreview()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The session setup would leave, as the copy opens over it.
    private var setupSession: BrowserSetupSession? {
        draftPreview.preview(of: setup, in: browser).map {
            BrowserSetupSession(seed: $0.seed(wearing: nil), images: $0.images)
        }
    }

    /// Whether the welcome fills the screen, before the steps or the
    /// take-over.
    private var isLanding: Bool {
        path.isEmpty && !isTakingOver
    }

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            let stepsWidth = MobilePadSetupMetrics.panelWidth(in: geometry.size.width)
            let sheetWidth = isTakingOver ? 0 : isLanding ? geometry.size.width : stepsWidth
            ZStack(alignment: .leading) {
                copy
                    .padding(.leading, isTakingOver ? 0 : stepsWidth)
                    .opacity(isLanding ? 0 : 1)
                    // Off the trailing edge on the welcome, it comes in with
                    // the sheet's edge, so the two never overlap.
                    .offset(x: isLanding ? geometry.size.width - stepsWidth : 0)
                    .allowsHitTesting(!isLanding)
                    .accessibilityHidden(isLanding)
                paper(width: sheetWidth)
                sheet(stepsWidth: stepsWidth, screenWidth: geometry.size.width, width: sheetWidth)
            }
            .background {
                // Gone once the copy fills the screen, so nothing of setup
                // shows through as the copy fades over Crest.
                BrowserSetupPaperRoom(look: live.shownLook)
                    .opacity(isTakingOver ? 0 : 1)
                    .ignoresSafeArea()
            }
            .animation(CrestMotion.onboardingSheet.unlessReducingMotion(reduceMotion), value: isLanding)
        }
        .onChange(of: setupSession, initial: true) { _, session in
            guard let session else { return }
            live.show(session.seed, images: session.images, spaceID: shownSpaceID)
        }
        .onChange(of: shownSpaceID) { _, spaceID in live.show(spaceID) }
        // Crest opens on the guide once setup finishes, so the copy shows it
        // too, ready before the copy grows into Crest.
        .onChange(of: isFinishing) { _, isFinishing in
            if isFinishing { live.showGettingStarted() }
        }
    }

    /// The sheet of paper setup lies on, from the top of the screen to the
    /// bottom, its trailing edge casting a shadow on the room.
    private func paper(width: CGFloat) -> some View {
        BrowserSetupPaper()
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .shadow(
                color: CrestBrandPalette.ink.opacity(isLanding ? 0 : MobilePadSetupMetrics.sheetShadow),
                radius: MobilePadSetupMetrics.sheetShadowRadius, x: MobilePadSetupMetrics.sheetShadowOffset
            )
            .opacity(isTakingOver ? 0 : 1)
            .ignoresSafeArea()
    }

    /// What lies on the sheet: the whole screen on the welcome, a third of it
    /// for the steps; it slides away as the copy takes over. What it holds
    /// keeps its own width as it slides, so nothing on it lays out again.
    private func sheet(stepsWidth: CGFloat, screenWidth: CGFloat, width: CGFloat) -> some View {
        MobileSetupSteps(
            browser: browser, setup: setup, welcome: welcome, standsAlone: false, closes: closes,
            errorMessage: errorMessage, isFinishing: isFinishing, isTakingOver: false, path: $path,
            shownSpaceID: $shownSpaceID, setUpWithoutCloud: setUpWithoutCloud,
            startBrowsing: { startBrowsing(live.edits) }, prepareCrest: prepareCrest, openCrest: openCrest,
            close: close
        )
        .frame(width: path.isEmpty ? screenWidth : stepsWidth)
        .frame(width: screenWidth, alignment: .leading)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .opacity(isTakingOver ? 0 : 1)
    }

    /// Crest over the live copy, at its real size in the room beside the
    /// steps, filling the screen once setup finishes.
    private var copy: some View {
        MobileSetupLiveWindow(
            session: live, cornerRadius: isTakingOver ? 0 : MobileSetupLiveWindowMetrics.cornerRadius
        )
        .shadow(
            color: CrestBrandPalette.ink.opacity(isTakingOver ? 0 : MobilePadSetupMetrics.copyShadow),
            radius: 30, y: 18
        )
        .padding(isTakingOver ? 0 : MobilePadSetupMetrics.copyInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MobilePadSetupMetrics {
    /// The steps take about a third of the screen, within these widths.
    static let panelWidths: ClosedRange<CGFloat> = 340...420
    static let copyInset: CGFloat = 32
    static let copyShadow = 0.3
    /// The shadow the sheet's edge casts on the room.
    static let sheetShadow = 0.2
    static let sheetShadowRadius: CGFloat = 16
    static let sheetShadowOffset: CGFloat = 4

    static func panelWidth(in width: CGFloat) -> CGFloat {
        min(max(width / 3, panelWidths.lowerBound), panelWidths.upperBound)
    }
}
