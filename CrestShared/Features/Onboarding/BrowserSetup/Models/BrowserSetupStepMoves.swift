import Foundation

/// How setup's steps move, the same on every platform: on to a page, to a step
/// from its chip, and back, by the walk the steps follow, the welcome's wait
/// on iCloud and the Space Your Space makes. Each panel keeps the pages open
/// and whether the last move went back, and lays the pages out itself.
@MainActor
struct BrowserSetupStepMoves {
    // MARK: - Variables

    let walk: BrowserSetupWalk
    let welcome: BrowserOnboardingWelcomeAction
    /// The Space Your Space makes: the first one the setup holds.
    let firstSpaceID: UUID?
    /// Leaves the welcome's wait on iCloud and sets up without it.
    let setUpWithoutCloud: () -> Void

    // MARK: - Actions - Reading

    /// Whether `path` is still at the welcome while it waits on iCloud and
    /// offers no way past it yet.
    func isCheckingCloud(_ path: [BrowserSetupDestination]) -> Bool {
        path.isEmpty && welcome.waitsOnCloud && !welcome.offersSetupWithoutCloud
    }

    // MARK: - Actions - Moving

    /// On to `destination`, in place of the pages open when `replacing`.
    func go(
        to destination: BrowserSetupDestination, replacing: Bool = false, path: inout [BrowserSetupDestination],
        isGoingBack: inout Bool, shownSpaceID: inout UUID?
    ) {
        isGoingBack = false
        if replacing { path = [destination] } else { path.append(destination) }
        if destination == .yourSpace, let firstSpaceID { shownSpaceID = firstSpaceID }
    }

    /// Opens `step` from its chip, sliding back or on as the step lies, and
    /// leaving the welcome's wait on iCloud as Continue does.
    func open(
        _ step: BrowserSetupStep, path: inout [BrowserSetupDestination], isGoingBack: inout Bool,
        shownSpaceID: inout UUID?
    ) {
        guard let page = walk.page(opening: step), path.first != page || path.count > 1 else { return }
        if path.isEmpty, welcome.waitsOnCloud { setUpWithoutCloud() }
        isGoingBack = walk.goesBack(to: step, from: path.first)
        path = [page]
        if page == .yourSpace, let firstSpaceID { shownSpaceID = firstSpaceID }
    }

    /// Up from a page deeper in a step, else to the step before, or from the
    /// first step to the welcome.
    func back(path: inout [BrowserSetupDestination], isGoingBack: inout Bool) {
        isGoingBack = true
        if path.count > 1 {
            path.removeLast()
        } else if let current = path.last, let before = walk.page(before: current) {
            path = [before]
        } else {
            path = []
        }
    }
}
