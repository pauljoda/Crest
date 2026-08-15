import Observation

@Observable
@MainActor
final class MobileBrowserNavigationState {
    private(set) var presentation: MobileBrowserPresentation = .compact
    private var compactPagePresentationPhase: MobileCompactPagePresentationPhase
    private(set) var regularSidebarIsPresented: Bool
    private(set) var compactToolbarIsHidden = false
    let utilityPresentation = BrowserUtilityPresentationState()

    init(
        regularSidebarIsPresented: Bool = true,
        initiallyShowsCompactPage: Bool = false
    ) {
        self.regularSidebarIsPresented = regularSidebarIsPresented
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

    func selectTab() {
        if presentation == .compact {
            compactToolbarIsHidden = false
            compactPagePresentationPhase = .presentingPage
        }
    }

    func showTabViewer() {
        compactToolbarIsHidden = false
        compactPagePresentationPhase = .tabViewer
    }

    func prepareForSpaceSwitch() {
        showTabViewer()
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
        regularSidebarIsPresented = true
    }

    func hideRegularSidebar() {
        regularSidebarIsPresented = false
    }

    func toggleRegularSidebar() {
        regularSidebarIsPresented.toggle()
    }

    func adapt(to presentation: MobileBrowserPresentation) {
        self.presentation = presentation
        if presentation == .regular {
            compactToolbarIsHidden = false
        }
    }
}
