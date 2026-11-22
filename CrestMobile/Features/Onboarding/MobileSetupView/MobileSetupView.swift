import SwiftUI

/// Setup on iPhone and iPad, as a Mac's: the steps on a sheet of Crest's
/// paper. An iPad held wide sets them beside Crest over a live copy of what
/// setup builds. A phone, or an iPad held upright, gives the steps the whole
/// screen, each Space's page wearing the Space's own look, with Preview to
/// see it as Crest will. Where setup has got to carries across a turn of the
/// device.
struct MobileSetupView: View {
    // MARK: - Variables

    let browser: BrowserStore
    let setup: BrowserManualSetupModel
    let welcome: BrowserOnboardingWelcomeAction
    /// The page setup opens on: the welcome, or the step the person came
    /// for.
    let firstPath: [BrowserSetupDestination]
    /// Whether setup was opened for one step, so it offers Cancel.
    let closes: Bool
    let errorMessage: String?
    /// Whether setup is finishing, which holds every action.
    let isFinishing: Bool
    /// Whether setup finished and an iPad's copy grows to fill the screen.
    var isTakingOver = false
    let setUpWithoutCloud: () -> Void
    /// Finishes setup, carrying what the person changed in an iPad's copy's
    /// tabs and folders into Crest.
    let startBrowsing: (BrowserSetupCopyEdits?) -> Void
    /// Brings Crest up behind setup, ready for when setup hands over to it.
    let prepareCrest: () -> Void
    let openCrest: () -> Void
    let close: () -> Void

    @State private var path: [BrowserSetupDestination] = []
    @State private var shownSpaceID: UUID?
    /// The live copy an iPad held wide shows beside the steps, kept here so a
    /// turn of the device keeps it and what the person changed in it.
    @State private var live = BrowserSetupLiveSession()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            if setsStepsBeside(in: geometry.size) {
                MobilePadSetup(
                    browser: browser, setup: setup, welcome: welcome, closes: closes, errorMessage: errorMessage,
                    isFinishing: isFinishing, isTakingOver: isTakingOver, live: live, path: $path,
                    shownSpaceID: $shownSpaceID, setUpWithoutCloud: setUpWithoutCloud, startBrowsing: startBrowsing,
                    prepareCrest: prepareCrest, openCrest: openCrest, close: close)
            } else {
                MobileSetupSteps(
                    browser: browser, setup: setup, welcome: welcome, standsAlone: true, closes: closes,
                    errorMessage: errorMessage, isFinishing: isFinishing, isTakingOver: isTakingOver, path: $path,
                    shownSpaceID: $shownSpaceID, setUpWithoutCloud: setUpWithoutCloud,
                    startBrowsing: { startBrowsing(live.edits) }, prepareCrest: prepareCrest, openCrest: openCrest,
                    close: close)
            }
        }
        .onAppear {
            if path.isEmpty { path = firstPath }
        }
        .onDisappear(perform: live.close)
    }

    // MARK: - Actions - Reading

    /// Whether a screen of `size` has room for the copy beside the steps: a
    /// regular width, held wide.
    private func setsStepsBeside(in size: CGSize) -> Bool {
        horizontalSizeClass == .regular && size.width > size.height && size.width >= MobileSetupViewMetrics.besideWidth
    }
}

enum MobileSetupViewMetrics {
    /// The narrowest width that sets the steps beside the copy.
    static let besideWidth: CGFloat = 700
}
