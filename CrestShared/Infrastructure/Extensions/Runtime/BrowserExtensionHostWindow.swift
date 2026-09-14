import Foundation

@MainActor
final class BrowserExtensionHostWindow {
    let id: BrowserWindowID
    weak var browser: (any BrowserExtensionTabWindowSessionHandling)?
    weak var pageProvider: (any BrowserExtensionPageProviding)?
    let focus: () -> Void
    let close: () -> Void

    init(
        id: BrowserWindowID, browser: any BrowserExtensionTabWindowSessionHandling,
        pageProvider: any BrowserExtensionPageProviding, focus: @escaping () -> Void, close: @escaping () -> Void
    ) {
        self.id = id
        self.browser = browser
        self.pageProvider = pageProvider
        self.focus = focus
        self.close = close
    }
}
