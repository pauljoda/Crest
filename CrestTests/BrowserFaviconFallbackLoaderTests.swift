import Foundation
import WebKit
import XCTest

@testable import Crest

final class BrowserFaviconFallbackLoaderTests: XCTestCase {
    @MainActor
    func testSVGIconCandidateRasterizesIntoImageIODecodableData() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let svgData = Data(
            #"""
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <rect width="24" height="24" rx="5" fill="#6864F6" />
              <circle cx="16" cy="8" r="5" fill="#4CC2FF" />
            </svg>
            """#.utf8
        )

        let candidateData = await BrowserFaviconCapture.rasterizedSVGData(
            svgData,
            in: webView,
            maximumPixelSize: 64
        )
        let rasterizedData = try XCTUnwrap(candidateData)

        XCTAssertNotNil(
            BrowserFaviconImageDecoder.decodeSynchronously(
                rasterizedData,
                maximumPixelSize: 64
            )
        )
    }

    @MainActor
    func testFaviconDiscoveryKeepsCrossOriginMicrosoftIconCandidates() throws {
        let pageURL = try XCTUnwrap(
            URL(string: "https://admin.microsoft.com/AdminPortal/Home")
        )
        let value: [String: Any] = [
            "userAgent": "Mozilla/5.0 Crest favicon fixture",
            "icons": [
                "https://res.cdn.office.net/admincenter/admin-favicon.ico",
                "/same-origin-icon.png",
            ],
            "manifests": ["/manifest.webmanifest"],
        ]

        let discovery = BrowserFaviconCapture.discovery(
            from: value,
            pageURL: pageURL
        )

        XCTAssertEqual(
            discovery.iconURLs,
            [
                URL(
                    string:
                        "https://res.cdn.office.net/admincenter/admin-favicon.ico"
                ),
                URL(string: "https://admin.microsoft.com/same-origin-icon.png"),
            ]
        )
        XCTAssertEqual(
            discovery.manifestURLs,
            [URL(string: "https://admin.microsoft.com/manifest.webmanifest")]
        )
        XCTAssertEqual(
            discovery.userAgent,
            "Mozilla/5.0 Crest favicon fixture"
        )
    }

    @MainActor
    func testFaviconDiscoveryPrefersBrowserIconOverAppleTouchArtwork() throws {
        let pageURL = try XCTUnwrap(
            URL(string: "https://admin.cloud.microsoft/?#/homepage")
        )
        let currentIcon = try XCTUnwrap(
            URL(
                string:
                    "https://res.public.onecdn.static.microsoft/admincenter/admin-content/images/ic_fluent_admincenter_24_color.svg"
            )
        )
        let legacyTouchIcon = try XCTUnwrap(
            URL(
                string:
                    "https://res.public.onecdn.static.microsoft/admincenter/admin-main/inline/330523bf2539b3de20ab.svg"
            )
        )
        let value: [String: Any] = [
            "icons": [
                [
                    "url": currentIcon.absoluteString,
                    "rel": "shortcut icon",
                    "sizes": "",
                ],
                [
                    "url": legacyTouchIcon.absoluteString,
                    "rel": "apple-touch-icon-precomposed",
                    "sizes": "512x512",
                ],
            ]
        ]

        let discovery = BrowserFaviconCapture.discovery(
            from: value,
            pageURL: pageURL
        )

        XCTAssertEqual(
            discovery.iconURLs,
            [currentIcon, legacyTouchIcon]
        )
    }

    @MainActor
    func testWebManifestScalableIconPrecedesLegacyPageFavicon() throws {
        let pageIcon = try XCTUnwrap(
            URL(string: "https://entra.microsoft.com/Content/favicon.ico")
        )
        let manifestURL = try XCTUnwrap(
            URL(
                string:
                    "https://entra.microsoft.com/Content/static/PWA/entra.webmanifest"
            )
        )
        let manifestData = Data(
            #"""
            {"icons":[
                {"src":"./Legacy.png","type":"image/png","sizes":"512x512"},
                {"src":"./Entra-Icon.svg","type":"image/svg+xml","sizes":"any"}
            ]}
            """#.utf8
        )
        let manifestIcons = BrowserFaviconCapture.manifestIconURLs(
            from: manifestData,
            manifestURL: manifestURL
        )

        XCTAssertEqual(
            manifestIcons.first,
            URL(
                string:
                    "https://entra.microsoft.com/Content/static/PWA/Entra-Icon.svg"
            )
        )
        XCTAssertEqual(
            BrowserFaviconCapture.prioritizedCandidateURLs(
                discoveredIconURLs: [pageIcon],
                manifestIconURLs: manifestIcons,
                fallbackURL: nil
            ).first,
            manifestIcons.first
        )
    }

    @MainActor
    func testWebManifestExcludesMaskableAndMonochromeInstallationIcons() throws {
        let manifestURL = try XCTUnwrap(
            URL(string: "https://video.example/manifest.webmanifest")
        )
        let manifestData = Data(
            #"""
            {"icons":[
                {"src":"normal-192.png","sizes":"192x192"},
                {"src":"monochrome-512.png","sizes":"512x512","purpose":"monochrome"},
                {"src":"maskable-512.png","sizes":"512x512","purpose":"maskable"},
                {"src":"general-maskable-256.png","sizes":"256x256","purpose":"any maskable"}
            ]}
            """#.utf8
        )

        XCTAssertEqual(
            BrowserFaviconCapture.manifestIconURLs(
                from: manifestData,
                manifestURL: manifestURL
            ),
            [
                try XCTUnwrap(
                    URL(string: "https://video.example/general-maskable-256.png")
                ),
                try XCTUnwrap(
                    URL(string: "https://video.example/normal-192.png")
                ),
            ]
        )
    }

    func testNativeFaviconCandidateRequestBypassesPageCORSAndStaleCaches() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            FaviconURLProtocolStub.lastRequest = nil
        }
        let iconData = Data([0x00, 0x00, 0x01, 0x00])
        FaviconURLProtocolStub.responseData = iconData
        let iconURL = try XCTUnwrap(
            URL(string: "https://res.cdn.office.net/admin-favicon.ico")
        )
        let pageURL = try XCTUnwrap(
            URL(string: "https://admin.microsoft.com/AdminPortal/Home")
        )

        let data = await BrowserFaviconCapture.downloadCandidate(
            iconURL,
            pageURL: pageURL,
            cookies: [],
            userAgent: "Mozilla/5.0 Crest favicon fixture",
            session: session
        )

        XCTAssertEqual(data, iconData)
        let request = try XCTUnwrap(FaviconURLProtocolStub.lastRequest)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), pageURL.absoluteString)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "Mozilla/5.0 Crest favicon fixture"
        )
    }

    func testFallbackRejectsHTMLReturnedFromACloudMicrosoftFaviconPath() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            FaviconURLProtocolStub.lastRequest = nil
            FaviconURLProtocolStub.contentType = "image/x-icon"
        }
        FaviconURLProtocolStub.responseData = Data("<html>login</html>".utf8)
        FaviconURLProtocolStub.contentType = "text/html; charset=utf-8"
        let iconURL = try XCTUnwrap(
            URL(string: "https://admin.cloud.microsoft/favicon.ico")
        )

        let data = await BrowserFaviconFallbackLoader.download(
            iconURL,
            session: session
        )

        XCTAssertNil(data)
    }

    func testProfileInvalidationPreventsAnOlderCompletionFromReplacingNewCacheState() async {
        let downloader = ControlledDownloader()
        let loader = BrowserFaviconFallbackLoader(download: downloader.download)
        let profileID = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xF0)
        )
        let pageURL = try! XCTUnwrap(URL(string: "https://fallback.invalid/page"))
        let oldData = Data([0x01, 0x02, 0x03])
        let newData = Data([0x04, 0x05, 0x06])

        let oldRequest = Task {
            await loader.data(for: pageURL, profileID: profileID)
        }
        let firstStarted = await downloader.waitForRequestCount(1)
        XCTAssertTrue(firstStarted)

        await loader.removeAll(for: profileID)

        let newRequest = Task {
            await loader.data(for: pageURL, profileID: profileID)
        }
        let secondStarted = await downloader.waitForRequestCount(2)
        XCTAssertTrue(secondStarted)

        await downloader.completeRequest(at: 1, with: newData)
        let newResult = await newRequest.value
        XCTAssertEqual(newResult, newData)

        await downloader.completeRequest(at: 0, with: oldData)
        let oldResult = await oldRequest.value
        XCTAssertNil(oldResult)

        let cachedResult = await loader.data(for: pageURL, profileID: profileID)
        XCTAssertEqual(cachedResult, newData)
        let requestCount = await downloader.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    /// A download that starts and finishes only when the test says so.
    ///
    /// Both directions are signalled rather than polled. Waiting for a start by
    /// yielding a fixed number of times made this test depend on how much CPU the
    /// machine had spare: under a concurrent build the loader's detached, utility
    /// priority download had not begun within the budget and the test failed on a
    /// machine where nothing was wrong. A continuation resumed by the download
    /// itself has no budget to run out of — if the download never starts, the test
    /// hangs and XCTest reports that instead of blaming the wrong thing.
    private actor ControlledDownloader {
        private var continuations: [CheckedContinuation<Data?, Never>] = []
        private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        var requestCount: Int { continuations.count }

        func download(_ url: URL) async -> Data? {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
                announceStart()
            }
        }

        /// Suspends until `expectedCount` downloads have started. Returns `true`
        /// once they have, so the caller can assert on the fact rather than
        /// assume it.
        func waitForRequestCount(_ expectedCount: Int) async -> Bool {
            guard continuations.count < expectedCount else { return true }
            await withCheckedContinuation { continuation in
                startWaiters.append((expectedCount, continuation))
            }
            return true
        }

        func completeRequest(at index: Int, with data: Data?) {
            continuations[index].resume(returning: data)
        }

        private func announceStart() {
            let startedCount = continuations.count
            let readyWaiters = startWaiters.filter { $0.count <= startedCount }
            startWaiters.removeAll { $0.count <= startedCount }
            for waiter in readyWaiters {
                waiter.continuation.resume()
            }
        }
    }

    private final class FaviconURLProtocolStub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var lastRequest: URLRequest?
        nonisolated(unsafe) static var responseData = Data()
        nonisolated(unsafe) static var contentType = "image/x-icon"

        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            Self.lastRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": Self.contentType]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.responseData)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
