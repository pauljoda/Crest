import XCTest
@testable import Crest

@MainActor
final class BrowserDefaultBrowserTests: XCTestCase {
    func testApplicationRegistersBothWebURLSchemes() throws {
        let urlTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
                as? [[String: Any]]
        )
        let schemes = Set(
            urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )

        XCTAssertTrue(schemes.contains("http"))
        XCTAssertTrue(schemes.contains("https"))
    }

    func testApplicationRegistersBrowserDocumentTypesUsedByTheSystemPicker() throws {
        let documentTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes")
                as? [[String: Any]]
        )
        let contentTypes = Set(
            documentTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        )
        let handlerRanksByName: [String: String] = Dictionary(
            uniqueKeysWithValues: documentTypes.compactMap { documentType -> (String, String)? in
                guard let name = documentType["CFBundleTypeName"] as? String,
                      let handlerRank = documentType["LSHandlerRank"] as? String else {
                    return nil
                }
                return (name, handlerRank)
            }
        )

        XCTAssertTrue(contentTypes.contains("public.html"))
        XCTAssertTrue(contentTypes.contains("public.xhtml"))
        XCTAssertEqual(handlerRanksByName["HTML document"], "Default")
        XCTAssertEqual(handlerRanksByName["XHTML document"], "Default")
    }

    func testExternalURLPolicyAcceptsOnlyHostBasedHTTPAndHTTPSURLs() throws {
        XCTAssertTrue(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "https://example.com/path?q=1"))
            )
        )
        XCTAssertTrue(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "http://127.0.0.1:8765/fixture"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "file:///tmp/index.html"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "crest://settings"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "https:///missing-host"))
            )
        )
    }

    func testExternalURLReusesASelectedStartPageThenCreatesANewCurrentTab() throws {
        let browser = BrowserStore.privateBrowsing()
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second"))
        let originalTabID = try XCTUnwrap(browser.selectedTab?.id)

        XCTAssertTrue(browser.openExternalURL(firstURL))
        XCTAssertEqual(browser.selectedTab?.id, originalTabID)
        XCTAssertEqual(browser.selectedTab?.url, firstURL)
        XCTAssertEqual(browser.selectedSpace?.currentTabs.count, 1)

        XCTAssertTrue(browser.openExternalURL(secondURL))
        XCTAssertNotEqual(browser.selectedTab?.id, originalTabID)
        XCTAssertEqual(browser.selectedTab?.url, secondURL)
        XCTAssertEqual(browser.selectedSpace?.currentTabs.count, 2)
    }

    func testRejectedExternalURLDoesNotMutateTheSession() throws {
        let browser = BrowserStore.privateBrowsing()
        let initialSession = browser.session
        let rejectedURL = try XCTUnwrap(URL(string: "file:///tmp/private.txt"))

        XCTAssertFalse(browser.openExternalURL(rejectedURL))
        XCTAssertEqual(browser.session, initialSession)
    }

    func testDefaultBrowserControllerOwnsExplicitStatusAndRequestFlow() async {
        var isSystemDefault = false
        var requestCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .direct,
            statusCheck: { isSystemDefault },
            defaultRequest: {
                requestCount += 1
                isSystemDefault = true
            },
            settingsOpener: {}
        )

        XCTAssertEqual(controller.status, .unknown)
        controller.refreshStatus()
        XCTAssertEqual(controller.status, .notDefault)

        await controller.requestDefault()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.status, .isDefault)
        XCTAssertFalse(controller.isWorking)
    }
}
