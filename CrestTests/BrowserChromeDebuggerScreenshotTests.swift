import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerScreenshotTests: XCTestCase {
    func testViewportCaptureContainsRealRenderedPixels() async throws {
        try await withPage { capture, page in
            let response = try await capture.capture(parameters: [:])
            let encoded = try XCTUnwrap(response["data"] as? String)
            let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
            XCTAssertEqual(Array(bytes.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: bytes))
            let nativeScale = try await page.evaluateJavaScript("devicePixelRatio")
            let scale = try XCTUnwrap(nativeScale as? Double)
            XCTAssertEqual(bitmap.pixelsWide, Int(640 * scale))
            XCTAssertEqual(bitmap.pixelsHigh, Int(480 * scale))
            XCTAssertEqual(rgbPixel(in: bitmap, x: 10, y: 10), [255, 0, 0])
        }
    }

    func testDocumentClipDoesNotChangeScrollPositionOrViewport() async throws {
        try await withPage { capture, page in
            _ = try await page.evaluateJavaScript("scrollTo(0, 400)")
            let before =
                try await page.evaluateJavaScript("JSON.stringify([scrollX,scrollY,innerWidth,innerHeight])") as? String
            let response = try await capture.capture(parameters: [
                "clip": ["x": 0, "y": 0, "width": 100, "height": 50, "scale": 1],
                "captureBeyondViewport": true,
            ])
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(response["data"] as? String)))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: bytes))
            let nativeScale = try await page.evaluateJavaScript("devicePixelRatio")
            let scale = try XCTUnwrap(nativeScale as? Double)
            XCTAssertEqual(bitmap.pixelsWide, Int(100 * scale))
            XCTAssertEqual(bitmap.pixelsHigh, Int(50 * scale))
            XCTAssertEqual(rgbPixel(in: bitmap, x: 10, y: 10), [255, 0, 0])
            let after =
                try await page.evaluateJavaScript("JSON.stringify([scrollX,scrollY,innerWidth,innerHeight])") as? String
            XCTAssertEqual(after, before)
        }
    }

    func testViewportCaptureUsesTheCurrentScrollPosition() async throws {
        try await withPage { capture, page in
            _ = try await page.evaluateJavaScript("scrollTo(0, 400)")
            let response = try await capture.capture(parameters: [:])
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(response["data"] as? String)))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: bytes))
            XCTAssertEqual(rgbPixel(in: bitmap, x: 10, y: 10), [0, 0, 255])
        }
    }

    func testCaptureBeyondViewportIncludesTheWholeDocumentWithoutResizing() async throws {
        try await withPage { capture, page in
            let before = page.frame
            let response = try await capture.capture(parameters: ["captureBeyondViewport": true])
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(response["data"] as? String)))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: bytes))
            let nativeScale = try await page.evaluateJavaScript("devicePixelRatio")
            let scale = try XCTUnwrap(nativeScale as? Double)
            XCTAssertEqual(bitmap.pixelsWide, Int(640 * scale))
            XCTAssertEqual(bitmap.pixelsHigh, Int(1200 * scale))
            XCTAssertEqual(rgbPixel(in: bitmap, x: 10, y: bitmap.pixelsHigh - 10), [0, 0, 255])
            XCTAssertEqual(page.frame, before)
        }
    }

    func testJPEGEncodingAndUnsupportedOptionsAreExplicit() async throws {
        try await withPage { capture, _ in
            let response = try await capture.capture(parameters: ["format": "jpeg", "quality": 80])
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(response["data"] as? String)))
            XCTAssertEqual(Array(bytes.prefix(2)), [255, 216])
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: bytes))
            let pixel = rgbPixel(in: bitmap, x: 10, y: 10)
            XCTAssertGreaterThan(pixel[0], 250)
            XCTAssertLessThan(pixel[1], 5)
            XCTAssertLessThan(pixel[2], 5)
            let rejected: [[String: Any]] = [
                ["format": "webp"], ["quality": 0.5], ["quality": true], ["fromSurface": false],
            ]
            for parameters in rejected {
                do {
                    _ = try await capture.capture(parameters: parameters)
                    XCTFail("Unsupported or invalid capture options must not silently change meaning: \(parameters)")
                } catch {}
            }
        }
    }

    private func rgbPixel(in bitmap: NSBitmapImageRep, x: Int, y: Int) -> [Int] {
        // colorAt converts through NSCalibratedRGBColorSpace. Verify the
        // encoded sRGB samples directly, without that unrelated conversion.
        XCTAssertEqual(bitmap.bitsPerSample, 8)
        XCTAssertEqual(bitmap.cgImage?.colorSpace?.name as String?, CGColorSpace.sRGB as String)
        var components = [Int](repeating: 0, count: bitmap.samplesPerPixel)
        bitmap.getPixel(&components, atX: x, y: y)
        return Array(components.prefix(3))
    }

    private func withPage(
        _ operation: (BrowserChromeDebuggerScreenshot, WKWebView) async throws -> Void
    ) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        page.loadHTMLString(
            """
            <!doctype html><title>Crest screenshot test</title>
            <style>html,body{margin:0}body{height:1200px;background:blue}div{height:200px;background:red}</style>
            <div></div>
            """, baseURL: nil)
        defer { page.stopLoading() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (try? await page.evaluateJavaScript("document.title")) as? String != "Crest screenshot test" {
            guard ContinuousClock.now < deadline else { throw BrowserWebInspectorProtocolError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        try await connection.connect()
        defer { connection.disconnect() }
        try await operation(BrowserChromeDebuggerScreenshot(connection: connection), page)
    }
}
