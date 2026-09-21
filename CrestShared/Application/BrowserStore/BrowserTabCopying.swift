import Foundation

/// The window's page owner can supply a current destination and native session
/// state before a validated copy becomes visible. No WebKit object is shared.
@MainActor
protocol BrowserTabCopying: AnyObject {
    func sourceForTabCopy(_ source: BrowserTab, in space: BrowserSpace) -> BrowserTab
    func prepareTabCopy(from source: BrowserTab, to copy: inout BrowserTab, in space: BrowserSpace)
}

extension BrowserTabCopying {
    func sourceForTabCopy(_ source: BrowserTab, in space: BrowserSpace) -> BrowserTab { source }
}
