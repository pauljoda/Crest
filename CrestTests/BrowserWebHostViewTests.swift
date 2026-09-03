import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebHostViewTests: XCTestCase {
    func testUnhandledWebKeyDoesNotReachTerminalInvalidInputFeedback() throws {
        let setup = focusHostSetup()
        let terminal = BrowserKeyboardTerminalProbe()
        setup.host.nextResponder = terminal
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        let event = try keyboardFallbackEvent(in: setup.window)

        setup.host.keyDown(with: event)

        XCTAssertTrue(terminal.unhandledSelectors.isEmpty)
        XCTAssertTrue(setup.host.nextResponder === terminal)
        XCTAssertNil(terminal.nextResponder)
        terminal.keyDown(with: event)
        XCTAssertEqual(terminal.unhandledSelectors, [#selector(NSResponder.keyDown(with:))])
    }

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

    func testNativeFieldOutsideTheWebViewKeepsItsNormalFallback() throws {
        let setup = focusHostSetup()
        let field = NSTextField(string: "Native field")
        setup.host.addSubview(field)
        XCTAssertTrue(setup.window.makeFirstResponder(field))
        let terminal = BrowserKeyboardTerminalProbe()
        setup.host.nextResponder = terminal

        setup.host.keyDown(with: try keyboardFallbackEvent(in: setup.window))

        XCTAssertEqual(terminal.unhandledSelectors, [#selector(NSResponder.keyDown(with:))])
    }

    func testNativeHandlerCanChangeTheResponderChainDuringWebFallback() throws {
        let setup = focusHostSetup()
        let handler = BrowserKeyboardHandlerProbe()
        let terminal = BrowserKeyboardTerminalProbe()
        let replacement = NSResponder()
        setup.host.nextResponder = handler
        handler.nextResponder = terminal
        handler.onKeyDown = { terminal.nextResponder = replacement }
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))

        setup.host.keyDown(with: try keyboardFallbackEvent(in: setup.window))

        XCTAssertEqual(handler.events.count, 1)
        XCTAssertTrue(terminal.nextResponder === replacement)
    }

    func testWebFallbackDoesNotChangeKeyUpRouting() throws {
        let setup = focusHostSetup()
        let terminal = BrowserKeyboardTerminalProbe()
        setup.host.nextResponder = terminal
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))

        setup.host.keyUp(with: try keyboardFallbackEvent(in: setup.window, type: .keyUp))

        XCTAssertEqual(terminal.unhandledSelectors, [#selector(NSResponder.keyUp(with:))])
        XCTAssertNil(terminal.nextResponder)
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

    func testAttachReplacesTheVisibleWebView() {
        let host = BrowserWebHostView()
        let first = WKWebView()
        let second = WKWebView()

        host.attach(first)
        host.attach(second)

        XCTAssertNil(first.superview)
        XCTAssertTrue(second.superview === host)
        XCTAssertEqual(host.subviews, [second])
    }

    func testAStaleHostCannotDetachAWebViewFromItsNewHost() {
        let oldHost = BrowserWebHostView()
        let newHost = BrowserWebHostView()
        let webView = WKWebView()

        oldHost.attach(webView)
        newHost.attach(webView)
        oldHost.detach()

        XCTAssertTrue(webView.superview === newHost)
    }

    func testAStaleHostCannotReattachAWebViewFromItsNewHost() {
        let oldHost = BrowserWebHostView()
        let newHost = BrowserWebHostView()
        let webView = WKWebView()

        oldHost.attach(webView)
        newHost.attach(webView)
        oldHost.attach(webView)

        XCTAssertTrue(webView.superview === newHost)
        XCTAssertEqual(newHost.subviews, [webView])
        XCTAssertTrue(oldHost.subviews.isEmpty)
    }

    func testHitTestingRoutesIntoTheAttachedWebView() {
        let host = BrowserWebHostView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400)
        )
        let webView = WKWebView(frame: host.bounds)

        host.attach(webView)
        host.layoutSubtreeIfNeeded()

        let hitView = host.hitTest(NSPoint(x: 250, y: 200))

        XCTAssertTrue(
            isView(hitView, containedIn: webView),
            "Hit testing the host's page area must resolve inside its attached WKWebView."
        )
    }

    func testAttachUsesFrameLayoutForWebKitsReparentedSurfaces() {
        let host = BrowserWebHostView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400)
        )
        let webView = WKWebView()

        host.attach(webView)
        host.setFrameSize(NSSize(width: 720, height: 540))

        XCTAssertTrue(webView.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(webView.autoresizingMask, [.width, .height])
        XCTAssertEqual(webView.frame, host.bounds)
        XCTAssertFalse(
            host.constraints.contains { constraint in
                constraint.firstItem === webView || constraint.secondItem === webView
            }
        )
    }

    func testAttachingAResidentPageToANewHostPreservesItsViewport() {
        let host = BrowserWebHostView()
        let viewport = NSRect(x: 0, y: 0, width: 720, height: 540)
        let webView = WKWebView(frame: viewport)

        host.attach(webView)

        XCTAssertEqual(webView.frame.size, viewport.size)
        host.setFrameSize(NSSize(width: 900, height: 600))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, host.bounds)
    }

    func testAnEmptyHostLayoutDoesNotDiscardAResidentViewport() {
        let viewport = NSRect(x: 0, y: 0, width: 720, height: 540)
        let host = BrowserWebHostView(frame: viewport)
        let webView = WKWebView(frame: viewport)
        host.attach(webView)

        host.setFrameSize(.zero)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(webView.frame.size, viewport.size)
        host.setFrameSize(NSSize(width: 900, height: 600))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, host.bounds)
    }

    func testLayoutRepairsAnAttachedPreloadedWebViewsStaleGeometry() {
        let host = BrowserWebHostView(
            frame: NSRect(x: 0, y: 0, width: 720, height: 540)
        )
        let webView = WKWebView()

        host.attach(webView)
        webView.frame = .zero
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            webView.frame,
            host.bounds,
            "A page that finished loading off screen must fill its host on first presentation."
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

    func testRememberedResponderCannotRestoreInAnotherWindow() {
        let first = focusHostSetup()
        let second = focusHostSetup()
        first.controller.remember(first.webView)
        first.controller.requestRestoration()
        XCTAssertTrue(second.window.makeFirstResponder(second.webView))

        XCTAssertFalse(
            first.controller.restoreIfNeeded(
                in: second.host,
                gate: .init(browserChromeOwnsFocus: false, pageChromeOwnsFocus: false),
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
        XCTAssertTrue(second.window.firstResponder === second.webView)
        XCTAssertFalse(first.controller.hasPendingRestoration)
    }

    func testFocusCaptureRecordsOnlyAResponderInsideTheWebView() {
        let setup = focusHostSetup()
        let externalField = NSTextField(string: "Chrome")
        setup.host.addSubview(externalField)

        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        setup.controller.captureBeforeDeparture()
        setup.controller.requestRestoration()
        XCTAssertTrue(setup.controller.hasPendingRestoration)

        XCTAssertTrue(setup.window.makeFirstResponder(externalField))
        setup.controller.captureBeforeDeparture()
        setup.controller.requestRestoration()
        XCTAssertFalse(
            setup.controller.hasPendingRestoration,
            "A URL field or other browser control must replace, not preserve, an old page candidate."
        )
    }

    func testRememberedWebViewResponderSurvivesATransientWindowOwner() {
        let setup = focusHostSetup()
        setup.controller.remember(setup.webView)
        XCTAssertTrue(setup.window.makeFirstResponder(nil))

        setup.controller.captureBeforeDeparture()
        setup.controller.requestRestoration()

        XCTAssertTrue(setup.controller.hasPendingRestoration)
    }

    func testHostTeardownDoesNotOverwriteThePagePoolsDepartureCapture() {
        let setup = focusHostSetup()
        let destinationControl = NSTextField(string: "Destination")
        setup.host.addSubview(destinationControl)
        setup.host.updateFocusPresentation(
            isPageActive: true,
            gate: .init(
                browserChromeOwnsFocus: false,
                pageChromeOwnsFocus: false
            )
        )

        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        setup.controller.captureBeforeDeparture()
        XCTAssertTrue(setup.window.makeFirstResponder(destinationControl))

        setup.host.detach()
        setup.controller.requestRestoration()

        XCTAssertTrue(
            setup.controller.hasPendingRestoration,
            "A dismantling host must not recapture after the page pool's authoritative transition."
        )
    }

    func testSamePageCandidateRestoresAfterAHostReplacement() {
        let setup = focusHostSetup()
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        setup.controller.captureBeforeDeparture()
        setup.host.detach()
        setup.controller.requestRestoration()

        let replacement = BrowserWebHostView(frame: setup.host.frame)
        setup.window.contentView = replacement
        replacement.attach(
            setup.webView,
            focusRestoration: setup.controller
        )
        XCTAssertTrue(replacement.focusRestoration === setup.controller)
        setup.window.makeKey()
        setup.window.makeFirstResponder(nil)

        XCTAssertTrue(
            setup.controller.restoreIfNeeded(
                in: replacement,
                gate: .init(
                    browserChromeOwnsFocus: false,
                    pageChromeOwnsFocus: false
                ),
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )

        XCTAssertTrue(setup.window.firstResponder === setup.webView)
        XCTAssertFalse(setup.controller.hasPendingRestoration)
    }

    func testStaleHostCannotRestoreAWebViewOwnedByANewHost() {
        let setup = focusHostSetup()
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        setup.controller.captureBeforeDeparture()
        setup.controller.requestRestoration()

        let replacement = BrowserWebHostView(frame: setup.host.frame)
        setup.window.contentView = replacement
        replacement.attach(
            setup.webView,
            focusRestoration: setup.controller
        )
        setup.host.attach(
            setup.webView,
            focusRestoration: setup.controller
        )
        setup.host.updateFocusPresentation(
            isPageActive: true,
            gate: .init(
                browserChromeOwnsFocus: false,
                pageChromeOwnsFocus: false
            )
        )

        XCTAssertTrue(setup.webView.superview === replacement)
        XCTAssertTrue(
            setup.controller.hasPendingRestoration,
            "The new host still owns the pending return."
        )
    }

    func testSuppressedReturnClearsTheCandidateInsteadOfRestoringLater() {
        let setup = focusHostSetup()
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        setup.controller.captureBeforeDeparture()
        setup.controller.requestRestoration()

        XCTAssertFalse(
            setup.controller.restoreIfNeeded(
                in: setup.host,
                gate: .suppressed,
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
        XCTAssertFalse(setup.controller.hasPendingRestoration)
        XCTAssertFalse(
            setup.controller.restoreIfNeeded(
                in: setup.host,
                gate: .init(
                    browserChromeOwnsFocus: false,
                    pageChromeOwnsFocus: false
                ),
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
    }

    func testExplicitOutgoingResidentWebViewCanYieldFocusToTheDestination() {
        let setup = focusHostSetup()
        let outgoingWebView = BrowserDesktopWebView(
            frame: setup.host.bounds,
            configuration: WKWebViewConfiguration()
        )
        setup.host.addSubview(outgoingWebView)
        setup.controller.remember(setup.webView)
        setup.controller.requestRestoration(displacing: outgoingWebView)
        XCTAssertTrue(setup.window.makeFirstResponder(outgoingWebView))

        XCTAssertTrue(
            setup.controller.restoreIfNeeded(
                in: setup.host,
                gate: .init(
                    browserChromeOwnsFocus: false,
                    pageChromeOwnsFocus: false
                ),
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
        XCTAssertTrue(setup.window.firstResponder === setup.webView)
        XCTAssertFalse(setup.controller.hasPendingRestoration)
    }

    func testUnexpectedResidentWebViewSuppressesRestoration() {
        let setup = focusHostSetup()
        let permittedOutgoingWebView = BrowserDesktopWebView(
            frame: setup.host.bounds,
            configuration: WKWebViewConfiguration()
        )
        let unexpectedWebView = BrowserDesktopWebView(
            frame: setup.host.bounds,
            configuration: WKWebViewConfiguration()
        )
        setup.host.addSubview(permittedOutgoingWebView)
        setup.host.addSubview(unexpectedWebView)
        setup.controller.remember(setup.webView)
        setup.controller.requestRestoration(
            displacing: permittedOutgoingWebView
        )
        XCTAssertTrue(setup.window.makeFirstResponder(unexpectedWebView))

        XCTAssertFalse(
            setup.controller.restoreIfNeeded(
                in: setup.host,
                gate: .init(
                    browserChromeOwnsFocus: false,
                    pageChromeOwnsFocus: false
                ),
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
        XCTAssertTrue(setup.window.firstResponder === unexpectedWebView)
        XCTAssertFalse(setup.controller.hasPendingRestoration)
    }

    func testAddressResignationFinishesBeforeANewerPageResponderTakesFocus() {
        let setup = focusHostSetup()
        let addressField = NSTextField(string: "https://example.com")
        setup.host.addSubview(addressField)
        XCTAssertTrue(setup.window.makeFirstResponder(addressField))

        AddressFocusAction.resign(in: setup.window)
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))

        XCTAssertTrue(
            setup.window.firstResponder === setup.webView,
            "A completed address resignation cannot race a destination page's restoration."
        )
    }

    func testAddressResignationClearsItsCurrentResponder() {
        let setup = focusHostSetup()
        let addressField = NSTextField(string: "https://example.com")
        setup.host.addSubview(addressField)
        XCTAssertTrue(setup.window.makeFirstResponder(addressField))

        AddressFocusAction.resign(in: setup.window)

        XCTAssertFalse(setup.window.firstResponder === addressField)
    }

    func testMenuTrackingMonitorUsesTrackingLifecycleNotHighlightedItems() {
        let notificationCenter = NotificationCenter()
        let monitor = BrowserMenuTrackingMonitor(
            notificationCenter: notificationCenter
        )
        let menu = NSMenu()

        XCTAssertFalse(monitor.isTracking)
        notificationCenter.post(
            name: NSMenu.didBeginTrackingNotification,
            object: menu
        )
        XCTAssertTrue(monitor.isTracking)
        notificationCenter.post(
            name: NSMenu.didEndTrackingNotification,
            object: menu
        )
        XCTAssertFalse(monitor.isTracking)
    }

    func testPresentationFocusProtectionBlocksOnlyTheMountingTurn() {
        let setup = focusHostSetup()
        XCTAssertTrue(setup.window.makeFirstResponder(nil))

        let staleGeneration =
            setup.controller.beginPresentationFocusProtection()
        let currentGeneration =
            setup.controller.beginPresentationFocusProtection()
        setup.controller.endPresentationFocusProtection(
            generation: staleGeneration
        )

        _ = setup.window.makeFirstResponder(setup.webView)
        XCTAssertFalse(setup.window.firstResponder === setup.webView)

        setup.controller.endPresentationFocusProtection(
            generation: currentGeneration
        )
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        XCTAssertTrue(setup.window.firstResponder === setup.webView)
    }

    func testNativeRefusalInvalidatesInsteadOfStealingFocusLater() {
        let refusingWindow = BrowserFocusRefusingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let setup = focusHostSetup(window: refusingWindow)
        XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
        setup.controller.captureBeforeDeparture()
        XCTAssertTrue(setup.window.makeFirstResponder(nil))
        setup.controller.requestRestoration()
        refusingWindow.rejectedResponder = setup.webView

        let allowed = BrowserWebFocusRestorationGate(
            browserChromeOwnsFocus: false,
            pageChromeOwnsFocus: false
        )

        XCTAssertFalse(
            setup.controller.restoreIfNeeded(
                in: setup.host,
                gate: allowed,
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
        XCTAssertEqual(refusingWindow.rejectedAttemptCount, 1)
        XCTAssertFalse(setup.controller.hasPendingRestoration)
        XCTAssertFalse(
            setup.controller.restoreIfNeeded(
                in: setup.host,
                gate: allowed,
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
        XCTAssertEqual(refusingWindow.rejectedAttemptCount, 1)
    }

    func testRealWebKitKeepsInputTextareaAndContenteditableSelections() async throws {
        let setup = focusHostSetup()
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/WebFocus/web-focus.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        setup.webView.loadSimulatedRequest(
            URLRequest(
                url: try XCTUnwrap(
                    URL(string: "https://web-focus.crest.test/")
                )
            ),
            responseHTML: html
        )
        try await waitUntil("the focus fixture to load") {
            let isLoaded =
                try? await setup.webView.evaluateJavaScript(
                    "document.querySelector('#input') !== null"
                ) as? Bool
            return isLoaded == true
        }

        for fixture in webFocusFixtures {
            XCTAssertTrue(setup.window.makeFirstResponder(setup.webView))
            try await setup.webView.evaluateJavaScript(fixture.prepareScript)
            setup.controller.captureBeforeDeparture()
            setup.host.detach()
            setup.host.attach(
                setup.webView,
                focusRestoration: setup.controller
            )
            setup.controller.requestRestoration()

            XCTAssertTrue(
                setup.controller.restoreIfNeeded(
                    in: setup.host,
                    gate: .init(
                        browserChromeOwnsFocus: false,
                        pageChromeOwnsFocus: false
                    ),
                    applicationIsActive: true,
                    accessibilityOwnsFocus: false,
                    menuIsTracking: false,
                    windowIsKey: true
                ),
                fixture.name
            )
            let selection =
                try await setup.webView.evaluateJavaScript(
                    fixture.inspectScript
                ) as? String
            XCTAssertEqual(selection, fixture.expectedSelection, fixture.name)
        }
    }

    private var webFocusFixtures: [WebFocusFixture] {
        [
            WebFocusFixture(
                name: "input",
                prepareScript:
                    "(() => { const element = document.querySelector('#input'); element.focus(); element.setSelectionRange(6, 11); })()",
                inspectScript:
                    "`${document.activeElement.id}:${document.activeElement.selectionStart}:${document.activeElement.selectionEnd}`",
                expectedSelection: "input:6:11"
            ),
            WebFocusFixture(
                name: "textarea",
                prepareScript:
                    "(() => { const element = document.querySelector('#textarea'); element.focus(); element.setSelectionRange(5, 12); })()",
                inspectScript:
                    "`${document.activeElement.id}:${document.activeElement.selectionStart}:${document.activeElement.selectionEnd}`",
                expectedSelection: "textarea:5:12"
            ),
            WebFocusFixture(
                name: "contenteditable",
                prepareScript: """
                    (() => {
                        const element = document.querySelector('#editor');
                        element.focus();
                        const range = document.createRange();
                        range.setStart(element.firstChild, 6);
                        range.setEnd(element.firstChild, 12);
                        const selection = window.getSelection();
                        selection.removeAllRanges();
                        selection.addRange(range);
                    })()
                    """,
                inspectScript: """
                    `${document.activeElement.id}:${window.getSelection().anchorOffset}:${window.getSelection().focusOffset}`
                    """,
                expectedSelection: "editor:6:12"
            ),
        ]
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
        BrowserWebFocusRestorationPolicy.allowsRestoration(
            hasPendingCandidate: true,
            candidateBelongsToWebView: true,
            gate: gate,
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

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(8),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description)")
    }

    private func isView(_ view: NSView?, containedIn ancestor: NSView) -> Bool {
        var candidate = view
        while let current = candidate {
            if current === ancestor {
                return true
            }
            candidate = current.superview
        }
        return false
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

private struct FocusHostSetup {
    let window: NSWindow
    let host: BrowserWebHostView
    let webView: WKWebView
    let controller: BrowserWebFocusRestorationController
}

private struct WebFocusFixture {
    let name: String
    let prepareScript: String
    let inspectScript: String
    let expectedSelection: String
}

@MainActor
private final class BrowserFocusRefusingWindow: NSWindow {
    weak var rejectedResponder: NSResponder?
    private(set) var rejectedAttemptCount = 0

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let rejectedResponder, responder === rejectedResponder {
            rejectedAttemptCount += 1
            return false
        }
        return super.makeFirstResponder(responder)
    }
}
