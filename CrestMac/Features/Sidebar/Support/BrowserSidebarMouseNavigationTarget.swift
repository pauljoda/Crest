import AppKit

/// What the auxiliary mouse buttons need from the page under the pointer.
///
/// Buttons 4 and 5 are Back and Forward when the pointer is over page content.
/// Deciding that by recognising one engine's view class made the gesture work
/// under WebKit and silently do nothing under Chromium, so the shell hands the
/// observer its live pages and the page answers for its own navigation.
@MainActor
protocol BrowserSidebarMouseNavigationTarget: AnyObject {
    var nativeView: NSView { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    func goBack()
    func goForward()
}

extension BrowserPage: BrowserSidebarMouseNavigationTarget {}
