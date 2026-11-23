import AppKit
import SwiftUI

/// Site Controls on the Mac, for the page a browser window, a split card or a
/// Quick Window shows: the window's commands run on it, as its menu bar and
/// keys run them, and the Mac's own parts, such as Developer Mode, the
/// engines a site opens in and the engine's extensions, are offered as data.
@MainActor
final class BrowserMacSiteControls: SiteControlsPlatform {
    // MARK: - Variables

    let configuration: BrowserSiteControlConfiguration
    /// The commands of the window that shows the page.
    let actions: BrowserCommandActions
    private let shortcuts: BrowserShortcutStore?
    private let close: @MainActor () -> Void

    var page: BrowserPlatformPage { configuration.page }
    var core: CrestCore { actions.browser.core }
    var space: SpaceModel? { configuration.space }
    var tab: TabStateModel? { configuration.selectedTabID.flatMap(configuration.space.shownTab) }
    var otherSpaceGroups: [[SpaceModel]] { configuration.page.otherSpaceGroups }
    var offersCertificates: Bool { true }
    var requestsDesktopSite: Bool? { nil }

    var certificateReview: (@MainActor () -> Void)? {
        configuration.page.certificateReviewAction()
    }

    var developerMode: SiteControlsDeveloperMode? {
        let page = configuration.page
        guard page.isDeveloperModeEnabled else { return nil }
        return SiteControlsDeveloperMode(isAutomatic: page.isDeveloperModeAutomatic) {
            page.setDeveloperToolbarVisible(false)
        }
    }

    var engineChoice: SiteControlsEngineChoice? {
        let page = configuration.page
        guard let engines = page.corePage.engines?.engines.map(\.kind), engines.count > 1,
            let current = page.corePage.state?.engine, let origin = page.live.displayURL.flatMap(SiteOrigin.init(url:))
        else { return nil }
        return SiteControlsEngineChoice(
            engines: engines, current: current,
            remember: { page.corePage.open(origin, in: page.spaceID, on: $0) },
            move: { page.corePage.move(to: $0) },
            logo: { BrowserEngineOption.logo(of: $0) })
    }

    var offersExtensions: Bool { BrowserEngineSiteControlsTiles.offers(configuration.page) }

    // MARK: - Initializers

    init(
        configuration: BrowserSiteControlConfiguration, actions: BrowserCommandActions,
        shortcuts: BrowserShortcutStore?, dismiss: @escaping @MainActor () -> Void
    ) {
        self.configuration = configuration
        self.actions = actions
        self.shortcuts = shortcuts
        close = dismiss
    }

    // MARK: - Actions - Actions

    func state(of action: SiteControlAction) -> SiteControlActionState {
        if let control = BrowserMacSiteControlAction.of(action) { return control.state(self) }
        guard let command = action.command else { return .notOffered }
        return SiteControlActionState(isAvailable: actions.canPerform(command), isOn: actions.isOn(command) ?? false)
    }

    func run(_ action: SiteControlAction) {
        if let control = BrowserMacSiteControlAction.of(action) {
            control.run(self)
        } else if let command = action.command {
            run(command)
        }
    }

    func canRun(_ command: ShortcutCommand) -> Bool {
        actions.canPerform(command)
    }

    /// Runs `command` once AppKit has let go of the control that asked, so a
    /// command that opens a panel or a sheet opens over the window.
    func run(_ command: ShortcutCommand) {
        let actions = actions
        Task { @MainActor in
            await Task.yield()
            actions.perform(command)
        }
    }

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        shortcuts?.shortcut(for: command) ?? command.defaultShortcut
    }

    // MARK: - Actions - Page

    func openPage(in space: SpaceModel) {
        guard let url = configuration.page.live.documentURL, ExternalWebLink.accepts(url) else { return }
        configuration.page.openInQuickWindow(url, in: space)
    }

    func toggleDesktopSite() {}

    func openSettings(_ destination: BrowserSettingsDestination) {
        guard let windowID = actions.targetWindowID else { return }
        actions.windows?.openSettings(
            destination, for: BrowserSpaceRuntimeAssignment(space: configuration.space), in: windowID)
    }

    func dismiss() {
        close()
    }
}

extension BrowserMacSiteControls {
    /// The engine a one-time move takes the page to: the first registered
    /// engine the page is not on.
    var otherEngine: EngineKind? {
        configuration.page.corePage.otherEngines.first
    }
}
