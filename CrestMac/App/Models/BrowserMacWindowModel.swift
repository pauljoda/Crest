import AppKit
import Observation

@Observable
@MainActor
final class BrowserMacWindowModel {
    let request: BrowserMacWindowRequest
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation = BrowserSpaceSettingsPresentationState()
    let windowState: BrowserWindowStateStore
    @ObservationIgnored weak var window: NSWindow?

    var id: BrowserWindowID { request.id }
    var isTemporary: Bool { request.kind == .temporary }

    init(
        request: BrowserMacWindowRequest, browser: BrowserStore, pages: BrowserPagePool,
        transientBrowsing: BrowserTransientBrowsingCoordinator, windowState: BrowserWindowStateStore
    ) {
        self.request = request
        self.browser = browser
        self.pages = pages
        self.transientBrowsing = transientBrowsing
        self.windowState = windowState
        chrome = BrowserChromeState(
            sidebarIsPresented: windowState.sidebarIsPresented ?? true,
            utilityPresentation: BrowserUtilityPresentationState(defaults: nil))
    }
}
