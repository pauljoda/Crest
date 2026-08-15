import WebKit
import XCTest
@testable import Crest

@MainActor
final class BrowserWebHostViewTests: XCTestCase {
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
