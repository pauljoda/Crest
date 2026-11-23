import Foundation

/// What one of Site Controls' actions with no command does on the Mac: how it
/// stands for the page and what it runs. Each action that has no command has
/// exactly one; the rest run their command.
@MainActor
struct BrowserMacSiteControlAction {
    // MARK: - Static Variables

    /// The one-time move to the engine the page is not on, named for it.
    static let openInOtherEngine = BrowserMacSiteControlAction(.openInOtherEngine) { controls in
        guard let engine = controls.otherEngine else { return .notOffered }
        return SiteControlActionState(
            title: "Open Page in \(String(localized: engine.title))", shortTitle: "\(String(localized: engine.title))")
    } run: { controls in
        guard let engine = controls.otherEngine else { return }
        controls.configuration.page.corePage.move(to: engine)
    }
    static let inspectElement = inspector(.inspectElement, panel: .elements)
    static let toggleConsole = inspector(.toggleConsole, panel: .console)
    static let toggleNetworkPanel = inspector(.toggleNetworkPanel, panel: .network)
    /// Developer Mode's reload menu: clears the site's cookies, which reloads
    /// the page.
    static let clearCookiesAndReload = BrowserMacSiteControlAction(.clearCookiesAndReload) { controls in
        SiteControlActionState(
            isAvailable: controls.configuration.page.isDeveloperModeEnabled && controls.canRun(.clearSiteCookies))
    } run: { controls in
        controls.run(.clearSiteCookies)
    }

    /// Every action without a command that the Mac runs.
    static let all = [openInOtherEngine, inspectElement, toggleConsole, toggleNetworkPanel, clearCookiesAndReload]

    // MARK: - Variables

    let action: SiteControlAction
    let state: @MainActor (BrowserMacSiteControls) -> SiteControlActionState
    let run: @MainActor (BrowserMacSiteControls) -> Void

    // MARK: - Initializers

    private init(
        _ action: SiteControlAction, state: @escaping @MainActor (BrowserMacSiteControls) -> SiteControlActionState,
        run: @escaping @MainActor (BrowserMacSiteControls) -> Void
    ) {
        self.action = action
        self.state = state
        self.run = run
    }

    /// An action that opens the inspector on `panel`, or closes it there.
    private static func inspector(_ action: SiteControlAction, panel: InspectorPanel) -> BrowserMacSiteControlAction {
        BrowserMacSiteControlAction(action) { controls in
            let page = controls.configuration.page
            return SiteControlActionState(
                isAvailable: page.live.documentURL != nil && page.pageEngine.registration.supports(.inspector),
                isOn: page.developerPanel == panel)
        } run: { controls in
            controls.configuration.page.toggleDeveloperPanel(panel)
        }
    }

    // MARK: - Actions - Lookup

    static func of(_ action: SiteControlAction) -> BrowserMacSiteControlAction? {
        all.first { $0.action == action }
    }
}
