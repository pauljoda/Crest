import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebHostViewTests: XCTestCase {
    func testWebKeyFallbackPreservesAnExistingNativeHandlerAndRepeat() throws {
        let setup = focusHostSetup()
        let handler = BrowserKeyboardHandlerProbe()
        let terminal = BrowserKeyboardTerminalProbe()
        setup.host.nextResponder = handler
        handler.nextResponder = terminal
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        let event = try keyboardFallbackEvent(in: setup.window, isRepeat: true)

        setup.host.keyDown(with: event)

        XCTAssertEqual(handler.events.count, 1)
        XCTAssertTrue(handler.events.first === event)
        XCTAssertTrue(terminal.unhandledSelectors.isEmpty)
        XCTAssertTrue(handler.nextResponder === terminal)
        XCTAssertNil(terminal.nextResponder)
    }

    /// A page sees a shortcut before Crest only while focus is in the page's
    /// own view; Crest's views beside it keep Crest's shortcuts first.
    func testOnlyThePageViewAndViewsInsideItArePageContent() {
        let setup = focusHostSetup()
        let inside = NSView()
        setup.webView.addSubview(inside)
        let field = NSTextField(string: "Native field")
        setup.host.addSubview(field)

        XCTAssertTrue(BrowserWebHostView.isPageContent(setup.webView))
        XCTAssertTrue(BrowserWebHostView.isPageContent(inside))
        XCTAssertFalse(BrowserWebHostView.isPageContent(setup.host))
        XCTAssertFalse(BrowserWebHostView.isPageContent(field))
        XCTAssertFalse(BrowserWebHostView.isPageContent(setup.window))
        XCTAssertFalse(BrowserWebHostView.isPageContent(nil))
    }

    /// A page view moving between hosts of one window never leaves it, which
    /// would hide its page from its engine and take its focus. SwiftUI makes
    /// the host a page moves to before it places it, and can dismantle the
    /// host the page leaves first, as when a page enters or leaves full
    /// screen; an older claim placed late never takes the view from a newer
    /// host.
    func testPageViewStaysInItsWindowAsItMovesBetweenHosts() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered,
            defer: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        window.contentView = root
        let page = BrowserWindowDepartureProbe(frame: root.bounds)
        let standard = BrowserWebHostView(frame: root.bounds)
        root.addSubview(standard)
        standard.attach(page)
        XCTAssertTrue(window.makeFirstResponder(page))

        let fullScreen = BrowserWebHostView(frame: root.bounds)
        fullScreen.attach(page)
        standard.dismantle()
        standard.removeFromSuperview()
        root.addSubview(fullScreen)
        XCTAssertTrue(page.superview === fullScreen)

        fullScreen.dismantle()
        fullScreen.removeFromSuperview()
        let late = BrowserWebHostView(frame: root.bounds)
        late.attach(page)
        let returning = BrowserWebHostView(frame: root.bounds)
        returning.attach(page)
        root.addSubview(returning)
        root.addSubview(late)
        XCTAssertTrue(page.superview === returning)

        XCTAssertEqual(page.windowDepartures, 0)
        XCTAssertTrue(window.firstResponder === page)
        returning.detach()
        late.detach()
    }

    private func keyboardFallbackEvent(
        in window: NSWindow,
        type: NSEvent.EventType = .keyDown,
        isRepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: 1,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "z",
                charactersIgnoringModifiers: "z",
                isARepeat: isRepeat,
                keyCode: 6
            )
        )
    }

    func testFocusPolicyRequiresAPermittedOwnerAndNoCompetingPresentation() {
        let allowed = BrowserWebFocusRestorationGate(
            browserChromeOwnsFocus: false,
            pageChromeOwnsFocus: false
        )

        XCTAssertTrue(
            restorationPolicyAllows(gate: allowed)
        )
        XCTAssertFalse(
            restorationPolicyAllows(
                gate: BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: true,
                    pageChromeOwnsFocus: false
                )
            )
        )
        XCTAssertFalse(
            restorationPolicyAllows(
                gate: BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: false,
                    pageChromeOwnsFocus: true
                )
            )
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, currentOwner: .other)
        )
        XCTAssertTrue(
            restorationPolicyAllows(
                gate: allowed,
                currentOwner: .departingWebContent
            )
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, windowHasAttachedSheet: true)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, menuIsTracking: true)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, accessibilityOwnsFocus: true)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, windowIsKey: false)
        )
        XCTAssertFalse(
            restorationPolicyAllows(gate: allowed, applicationIsActive: false)
        )
    }

    private func restorationPolicyAllows(
        gate: BrowserWebFocusRestorationGate,
        currentOwner: BrowserWebFocusRestorationCurrentOwner = .neutral,
        windowHasAttachedSheet: Bool = false,
        menuIsTracking: Bool = false,
        accessibilityOwnsFocus: Bool = false,
        windowIsKey: Bool = true,
        applicationIsActive: Bool = true
    ) -> Bool {
        gate.allowsRestoration(
            hasPendingCandidate: true,
            candidateBelongsToWebView: true,
            windowIsKey: windowIsKey,
            applicationIsActive: applicationIsActive,
            windowHasAttachedSheet: windowHasAttachedSheet,
            menuIsTracking: menuIsTracking,
            accessibilityOwnsFocus: accessibilityOwnsFocus,
            currentOwner: currentOwner
        )
    }

    private func focusHostSetup(window providedWindow: NSWindow? = nil) -> FocusHostSetup {
        let host = BrowserWebHostView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )
        let window =
            providedWindow
            ?? NSWindow(
                contentRect: host.frame,
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
        let webView = BrowserDesktopWebView(
            frame: host.bounds,
            configuration: WKWebViewConfiguration()
        )
        let controller = BrowserWebFocusRestorationController(webView: webView)
        webView.focusRestoration = controller
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.attach(webView, focusRestoration: controller)
        addTeardownBlock {
            window.orderOut(nil)
            host.detach()
        }
        return FocusHostSetup(
            window: window,
            host: host,
            webView: webView,
            controller: controller
        )
    }
}

@MainActor
private final class BrowserKeyboardTerminalProbe: NSResponder {
    var unhandledSelectors: [Selector] = []

    override func noResponder(for eventSelector: Selector) {
        unhandledSelectors.append(eventSelector)
    }
}

@MainActor
private final class BrowserKeyboardHandlerProbe: NSResponder {
    var events: [NSEvent] = []
    var onKeyDown: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        events.append(event)
        onKeyDown?()
    }
}

@MainActor
private final class BrowserWindowDepartureProbe: NSView {
    var windowDepartures = 0

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { windowDepartures += 1 }
    }
}

private struct FocusHostSetup {
    let window: NSWindow
    let host: BrowserWebHostView
    let webView: WKWebView
    let controller: BrowserWebFocusRestorationController
}
