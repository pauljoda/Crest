import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageConfigurationTests: XCTestCase {
    // MARK: - Actions - Configuration

    func testProductionConfigurationUsesTheSpacesPersistentStoreAndDesktopBrowserDefaults() {
        let profile = BrowsingProfile()

        let configuration = BrowserPageConfiguration.make(
            for: profile,
            websiteDataStore: BrowserWebsiteDataStore.persistent(for: profile)
        )

        XCTAssertEqual(configuration.websiteDataStore.identifier, profile.id)
        XCTAssertEqual(
            configuration.applicationNameForUserAgent,
            BrowserPlatformUserAgent.applicationName
        )
        XCTAssertEqual(configuration.defaultWebpagePreferences.preferredContentMode, .desktop)
        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(configuration.allowsAirPlayForMediaPlayback)
        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
        XCTAssertFalse(
            configuration.preferences.javaScriptCanOpenWindowsAutomatically,
            "Automatic windows are blocked until the site has explicit permission; user-activated windows are unaffected by this WebKit setting."
        )
        XCTAssertEqual(configuration.preferences.inactiveSchedulingPolicy, .suspend)
        XCTAssertTrue(configuration.upgradeKnownHostsToHTTPS)
        XCTAssertFalse(configuration.suppressesIncrementalRendering)
        XCTAssertFalse(configuration.limitsNavigationsToAppBoundDomains)
    }

    func testTheFactoryHonoursARequestedContentModeAndPlatformDecoration() {
        let profile = BrowsingProfile()
        var decoratedConfigurations = 0

        let configuration = BrowserPageConfiguration.make(
            for: profile,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            preferredContentMode: .recommended
        ) { configuration in
            decoratedConfigurations += 1
            configuration.suppressesIncrementalRendering = true
        }

        XCTAssertEqual(decoratedConfigurations, 1)
        XCTAssertEqual(
            configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
        XCTAssertTrue(
            configuration.suppressesIncrementalRendering,
            "A platform decoration runs last so it can override a shared default."
        )
        XCTAssertEqual(
            configuration.preferences.inactiveSchedulingPolicy,
            .suspend,
            "Every platform gets the shared WebKit settings the factory owns."
        )
        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
    }

    func testProductionWebViewAdvertisesDesktopSafariCompatibility() async throws {
        let profile = BrowsingProfile()
        let applicationName = try XCTUnwrap(BrowserPlatformUserAgent.applicationName)
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(for: profile)
        )

        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String

        XCTAssertEqual(
            userAgent?.hasSuffix(applicationName),
            true
        )
        XCTAssertFalse(userAgent?.contains("Crest/") == true)
    }

    func testDesktopWebViewAcceptsTheClickThatActivatesItsWindow() {
        let webView = BrowserDesktopWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(for: BrowsingProfile())
        )

        XCTAssertTrue(webView.acceptsFirstMouse(for: nil))
    }

    func testPrivateConfigurationUsesTheSuppliedNonPersistentStore() {
        let profile = BrowsingProfile()
        let dataStore = WKWebsiteDataStore.nonPersistent()

        let configuration = BrowserPageConfiguration.make(
            for: profile,
            websiteDataStore: dataStore
        )

        XCTAssertTrue(configuration.websiteDataStore === dataStore)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertNil(configuration.websiteDataStore.identifier)
    }

    // MARK: - Actions - Input

    func testControlWheelZoomsAPDFButLeavesOtherWheelInputAndHTMLAlone() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = BrowserDesktopWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }

        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 100, y: 100, width: 200, height: 300))
        context.endPDFPage()
        context.closePDF()
        view.load(
            data as Data, mimeType: "application/pdf", characterEncodingName: "",
            baseURL: URL(string: "https://example.test/document")!)
        try await waitUntil("the PDF document to finish loading") {
            view.value(forKey: "_isDisplayingPDF") as? Bool == true && !view.isLoading
        }

        let initial = view.magnification
        view.scrollWheel(with: try wheel(delta: 10, flags: .maskControl))
        try await waitUntil("Control-wheel to increase PDF magnification") { view.magnification > initial }
        let enlarged = view.magnification
        for flags: CGEventFlags in [[], .maskCommand, [.maskControl, .maskShift]] {
            view.scrollWheel(with: try wheel(delta: 10, flags: flags))
            XCTAssertEqual(view.magnification, enlarged)
        }
        view.scrollWheel(with: try wheel(delta: -10, flags: .maskControl))
        try await waitUntil("Control-wheel to decrease PDF magnification") { view.magnification < enlarged }

        view.loadHTMLString("<html><body style='height:2000px'>Scroll fixture</body></html>", baseURL: nil)
        try await waitUntil("the HTML document to replace the PDF") {
            view.value(forKey: "_isDisplayingPDF") as? Bool == false && !view.isLoading
        }
        let htmlMagnification = view.magnification
        view.scrollWheel(with: try wheel(delta: 10, flags: .maskControl))
        XCTAssertEqual(view.magnification, htmlMagnification)
    }

    private func wheel(delta: Int32, flags: CGEventFlags) throws -> NSEvent {
        let event = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        event.flags = flags
        event.location = CGPoint(x: 320, y: 240)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    private func waitUntil(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description)")
        throw NSError(domain: "BrowserPDFWheelInputTests", code: 1)
    }
}
