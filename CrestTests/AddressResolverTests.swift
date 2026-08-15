import AppKit
import XCTest
@testable import Crest

final class AddressResolverTests: XCTestCase {
    func testBareDomainUsesSecureHTTP() throws {
        let resolved = try XCTUnwrap(AddressResolver.resolve("apple.com"))

        XCTAssertEqual(resolved.absoluteString, "https://apple.com")
    }

    func testFullURLIsPreserved() throws {
        let resolved = try XCTUnwrap(AddressResolver.resolve("https://webkit.org/blog/"))

        XCTAssertEqual(resolved.absoluteString, "https://webkit.org/blog/")
    }

    func testLocalhostWithAPortOpensDirectlyUsingLocalHTTP() throws {
        let intent = try XCTUnwrap(AddressResolver.intent("localhost:3000"))

        XCTAssertEqual(
            intent,
            .open(try XCTUnwrap(URL(string: "http://localhost:3000")))
        )
    }

    func testLocalhostKeepsItsPathAndQuery() throws {
        let resolved = try XCTUnwrap(
            AddressResolver.resolve("localhost:5173/dashboard?mode=preview")
        )

        XCTAssertEqual(
            resolved.absoluteString,
            "http://localhost:5173/dashboard?mode=preview"
        )
    }

    func testWordsBecomeASearch() throws {
        let resolved = try XCTUnwrap(AddressResolver.resolve("native mac browser"))
        let components = try XCTUnwrap(URLComponents(url: resolved, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.queryItems?.first?.value, "native mac browser")
    }

    func testEachSpaceCanResolveTheSameQueryWithItsOwnSearchProvider() throws {
        let expectedHosts: [BrowserSearchProvider: String] = [
            .google: "www.google.com",
            .duckDuckGo: "duckduckgo.com",
            .bing: "www.bing.com",
            .ecosia: "www.ecosia.org",
            .brave: "search.brave.com"
        ]

        for provider in BrowserSearchProvider.allCases {
            let resolved = try XCTUnwrap(
                AddressResolver.resolve(
                    "space private search",
                    searchProvider: provider
                )
            )
            let components = try XCTUnwrap(
                URLComponents(url: resolved, resolvingAgainstBaseURL: false)
            )

            XCTAssertEqual(components.host, expectedHosts[provider])
            XCTAssertEqual(components.queryItems?.first?.value, "space private search")
        }
    }

    func testEverySearchProviderHasAUniqueLogoInTheApplicationAssetCatalog() {
        let logoNames = BrowserSearchProvider.allCases.map(\.logoAssetName)

        XCTAssertEqual(Set(logoNames).count, BrowserSearchProvider.allCases.count)
        for provider in BrowserSearchProvider.allCases {
            XCTAssertNotNil(
                NSImage(named: provider.logoAssetName),
                "Missing logo asset for \(provider.title)"
            )
        }
    }

    func testWhitespaceDoesNotNavigate() {
        XCTAssertNil(AddressResolver.resolve("   "))
    }

    func testAddressIntentDistinguishesWebsitesFromSearches() throws {
        let website = try XCTUnwrap(
            AddressResolver.intent("webkit.org/blog/", searchProvider: .duckDuckGo)
        )
        let search = try XCTUnwrap(
            AddressResolver.intent("webkit process model", searchProvider: .duckDuckGo)
        )

        XCTAssertEqual(
            website,
            .open(try XCTUnwrap(URL(string: "https://webkit.org/blog/")))
        )
        XCTAssertEqual(
            search,
            .search(
                query: "webkit process model",
                provider: .duckDuckGo,
                url: try XCTUnwrap(
                    URL(string: "https://duckduckgo.com/?q=webkit%20process%20model")
                )
            )
        )
    }

    func testCommandActionNamesTheSelectedSearchProvider() throws {
        let website = try XCTUnwrap(
            BrowserCommandActionPresentation(
                query: "apple.com/mac",
                searchProvider: .brave
            )
        )
        let search = try XCTUnwrap(
            BrowserCommandActionPresentation(
                query: "native webkit browser",
                searchProvider: .brave
            )
        )

        XCTAssertEqual(website.title, "Open apple.com")
        XCTAssertEqual(website.symbol, "globe")
        XCTAssertEqual(search.title, "Search with Brave Search")
        XCTAssertEqual(search.subtitle, "native webkit browser")
        XCTAssertEqual(search.symbol, "magnifyingglass")
    }
}
