import Foundation
import Observation

@Observable
@MainActor
final class MobileBrowserNavigationState {
    private(set) var presentation: MobileBrowserPresentation = .compact
    private var compactPagePresentationPhase: MobileCompactPagePresentationPhase
    private(set) var regularSidebarPresentation: BrowserSidebarPresentation
    private(set) var compactToolbarIsHidden = false
    let utilityPresentation = BrowserUtilityPresentationState()

    @ObservationIgnored
    private let transientSidebarDismissalDelay: Duration
    @ObservationIgnored
    private var transientSidebarDismissalTask: Task<Void, Never>?
    @ObservationIgnored
    private var transientSidebarDismissalIsPaused = false
    @ObservationIgnored
    private var lockedSpaceKeepsSidebarVisible = false

    init(
        regularSidebarIsPresented: Bool = true,
        initiallyShowsCompactPage: Bool = false,
        transientSidebarDismissalDelay: Duration = .seconds(5)
    ) {
        regularSidebarPresentation =
            regularSidebarIsPresented
            ? .docked
            : .collapsed
        self.transientSidebarDismissalDelay = transientSidebarDismissalDelay
        compactPagePresentationPhase =
            initiallyShowsCompactPage
            ? .page
            : .tabViewer
    }

    var defersPageActivation: Bool {
        presentation == .compact && !compactShowsPage
    }

    var compactShowsPage: Bool {
        switch compactPagePresentationPhase {
        case .presentingPage, .page:
            true
        case .tabViewer:
            false
        }
    }

    var compactPageIsFullyPresented: Bool {
        compactPagePresentationPhase == .page
    }

    var compactTabViewerChromeIsVisible: Bool {
        compactPagePresentationPhase == .tabViewer
    }

    var regularSidebarIsPresented: Bool {
        regularSidebarPresentation.showsSidebar
    }

    var regularSidebarIsDocked: Bool {
        regularSidebarPresentation == .docked
    }

    /// A narrow phone's full-screen tab viewer is its docked sidebar. Once the
    /// page is presented, the shared sidebar can only be floating or collapsed;
    /// a persisted regular-width dock state must not force the phone into the
    /// expanded shell.
    var compactSidebarPresentation: BrowserSidebarPresentation {
        guard compactShowsPage else { return .docked }
        return regularSidebarPresentation == .floating
            ? .floating
            : .collapsed
    }

    func selectTab() {
        if presentation == .compact {
            if compactPagePresentationPhase == .tabViewer {
                // The full-screen phone tab viewer is the docked sidebar. A
                // normal row selection must therefore enter the original
                // docked detail flow even if a prior window session last used
                // the floating sidebar. The Undock button takes the separate
                // toggleCompactSidebar path and keeps the floating mode.
                dockRegularSidebar()
            }
            compactToolbarIsHidden = false
            compactPagePresentationPhase = .presentingPage
        }
    }

    func showTabViewer() {
        compactToolbarIsHidden = false
        compactPagePresentationPhase = .tabViewer
        if presentation == .compact {
            dockRegularSidebar()
        }
    }

    func prepareForSpaceSwitch() {
        showTabViewer()
    }

    /// A lock is a privacy-state change inside the selected Space, not a new
    /// navigation mode. Keep the sidebar presentation the user is already in:
    /// a docked phone returns to its full-screen tab viewer, while a floating
    /// or collapsed sidebar becomes a persistent floating lock surface over
    /// the existing window.
    func prepareForLockedSpace() {
        lockedSpaceKeepsSidebarVisible = true
        compactToolbarIsHidden = false

        if presentation == .compact {
            if compactShowsPage, regularSidebarPresentation != .docked {
                cancelTransientSidebarDismissal()
                regularSidebarPresentation = .floating
            } else {
                showTabViewer()
            }
            return
        }

        cancelTransientSidebarDismissal()
        if regularSidebarPresentation == .collapsed {
            regularSidebarPresentation = .floating
        }
    }

    func finishLockedSpaceTransition() -> MobileBrowserSpaceSwitchDestination {
        lockedSpaceKeepsSidebarVisible = false
        return MobileBrowserSpaceSwitchPolicy.destinationAfterLeavingLockedSpace(
            in: presentation,
            sidebarPresentation: regularSidebarPresentation
        )
    }

    func hideCompactToolbar() {
        guard presentation == .compact, compactShowsPage else { return }
        compactToolbarIsHidden = true
    }

    func showCompactToolbar() {
        compactToolbarIsHidden = false
    }

    func completePagePresentation() {
        guard compactPagePresentationPhase == .presentingPage else { return }
        compactPagePresentationPhase = .page
    }

    /// The stable view state changes
    /// immediately while SwiftUI supplies only the visual morph between it and
    /// the selected tab row. There is no modal dismissal phase to stall in.
    func dismissPageToTabViewer() {
        showTabViewer()
    }

    func showSidebar() {
        showTabViewer()
    }

    func showRegularSidebar() {
        regularSidebarPresentation = .floating
        scheduleTransientSidebarDismissal()
    }

    func dockRegularSidebar() {
        cancelTransientSidebarDismissal()
        regularSidebarPresentation = .docked
    }

    func hideRegularSidebar() {
        cancelTransientSidebarDismissal()
        regularSidebarPresentation = .collapsed
    }

    func toggleRegularSidebar() {
        switch regularSidebarPresentation {
        case .collapsed:
            showRegularSidebar()
        case .floating:
            dockRegularSidebar()
        case .docked:
            hideRegularSidebar()
        }
    }

    /// Uses the same three sidebar states as regular-width windows while
    /// adapting only what "docked" means on a narrow phone.
    func toggleCompactSidebar() {
        switch compactSidebarPresentation {
        case .docked:
            showRegularSidebar()
            compactToolbarIsHidden = false
            compactPagePresentationPhase = .presentingPage
        case .floating:
            showTabViewer()
        case .collapsed:
            showRegularSidebar()
        }
    }

    func handleRegularSidebarInteraction() {
        scheduleTransientSidebarDismissal()
    }

    func handleRegularPageInteraction() {
        guard regularSidebarPresentation == .floating else { return }
        hideRegularSidebar()
    }

    func setTransientSidebarDismissalPaused(_ isPaused: Bool) {
        guard transientSidebarDismissalIsPaused != isPaused else { return }
        transientSidebarDismissalIsPaused = isPaused
        if isPaused {
            transientSidebarDismissalTask?.cancel()
            transientSidebarDismissalTask = nil
        } else {
            scheduleTransientSidebarDismissal()
        }
    }

    func adapt(to presentation: MobileBrowserPresentation) {
        self.presentation = presentation
        if presentation == .regular {
            compactToolbarIsHidden = false
        }
    }

    private func scheduleTransientSidebarDismissal() {
        guard regularSidebarPresentation == .floating,
            !transientSidebarDismissalIsPaused,
            !lockedSpaceKeepsSidebarVisible
        else { return }
        transientSidebarDismissalTask?.cancel()
        let delay = transientSidebarDismissalDelay
        transientSidebarDismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hideRegularSidebar()
        }
    }

    private func cancelTransientSidebarDismissal() {
        transientSidebarDismissalTask?.cancel()
        transientSidebarDismissalTask = nil
        transientSidebarDismissalIsPaused = false
    }
}
