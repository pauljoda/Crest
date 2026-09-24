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
        let expectedHosts: [SearchProvider: String] = [
            .google: "www.google.com",
            .duckDuckGo: "duckduckgo.com",
            .bing: "www.bing.com",
            .ecosia: "www.ecosia.org",
            .brave: "search.brave.com",
        ]

        for provider in SearchProvider.all {
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

    func testLegacySpacePreferencesDecodeWithoutChangingTheSelectedBuiltInProvider() throws {
        let legacyJSON = """
            {
              "searchProvider": "duckDuckGo",
              "currentTabCleanupPolicy": "after24Hours"
            }
            """

        let decoded = try JSONDecoder().decode(
            BrowserSpaceBrowsingPreferences.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(decoded.searchProvider, .duckDuckGo)
        XCTAssertEqual(decoded.availableSearchProviders, SearchProvider.all)
        XCTAssertTrue(decoded.customSearchProviders.isEmpty)
        XCTAssertFalse(decoded.searchSuggestionsEnabled)
    }

    func testCustomSelectionPersistsWithABuiltInFallbackForOlderBuilds() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000253")!
        let custom = BrowserCustomSearchProvider(
            id: id,
            name: "Example Search",
            searchURLTemplate: "https://search.example.com/results?q={searchTerms}",
            suggestionURLTemplate: "https://search.example.com/suggest?q={searchTerms}"
        )
        let preferences = BrowserSpaceBrowsingPreferences(
            searchProvider: custom.provider,
            currentTabCleanupPolicy: .after12Hours,
            customSearchProviders: [custom]
        )

        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBrowsingPreferences.self,
            from: encoded
        )

        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(decoded.searchProvider, custom.provider)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        // A custom engine is stored and synced as `custom:` and its lowercase identity.
        XCTAssertEqual(
            object["selectedSearchProviderID"] as? String, "custom:00000000-0000-0000-0000-000000000253")
        XCTAssertEqual(
            object["searchProvider"] as? String,
            "google",
            "An older Crest build must decode a safe built-in fallback when the new selection is custom."
        )
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

}
