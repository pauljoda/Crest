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
            .brave: "search.brave.com",
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
        let logoNames = BrowserSearchProvider.allCases.compactMap(\.logoAssetName)

        XCTAssertEqual(Set(logoNames).count, BrowserSearchProvider.allCases.count)
        for provider in BrowserSearchProvider.allCases {
            let logoAssetName = provider.logoAssetName
            XCTAssertNotNil(
                logoAssetName.flatMap(NSImage.init(named:)),
                "Missing logo asset for \(provider.title)"
            )
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
        XCTAssertEqual(decoded.availableSearchProviders, BrowserSearchProvider.allCases)
        XCTAssertTrue(decoded.customSearchProviders.isEmpty)
        XCTAssertFalse(decoded.searchSuggestionsEnabled)
    }

    func testKagiTemplatesProduceOneStableCustomProviderAndEncodeTheQueryExactlyOnce() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000264")!
        let kagi = try BrowserCustomSearchProvider(
            id: id,
            name: "Kagi",
            searchURLTemplate: "https://kagi.com/search?q=%s",
            suggestionURLTemplate: "https://kagi.com/api/autosuggest?q=%s"
        )
        var preferences = BrowserSpaceBrowsingPreferences.default

        try preferences.upsertCustomSearchProvider(kagi)
        preferences.searchProvider = kagi.provider

        XCTAssertEqual(preferences.searchProvider.id, .custom(id))
        XCTAssertEqual(preferences.searchProvider.title, "Kagi")
        XCTAssertEqual(
            preferences.searchProvider.searchURL(for: "Café + Swift/URL & WebKit")?.absoluteString,
            "https://kagi.com/search?q=Caf%C3%A9%20%2B%20Swift%2FURL%20%26%20WebKit"
        )
        XCTAssertEqual(
            preferences.searchProvider.suggestionURL(for: "crest browser")?.absoluteString,
            "https://kagi.com/api/autosuggest?q=crest%20browser"
        )
        XCTAssertEqual(preferences.searchProvider.iconPageURL?.absoluteString, "https://kagi.com/")
    }

    func testCustomProviderIdentitySurvivesEditingAndPreferenceRoundTrips() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000253")!
        var preferences = BrowserSpaceBrowsingPreferences.default
        let original = try BrowserCustomSearchProvider(
            id: id,
            name: "Example",
            searchURLTemplate: "https://search.example.com/?q=%s"
        )
        try preferences.upsertCustomSearchProvider(original)
        preferences.searchProvider = original.provider
        let edited = try BrowserCustomSearchProvider(
            id: id,
            name: "Example Search",
            searchURLTemplate: "https://search.example.com/results?q={searchTerms}",
            suggestionURLTemplate: "https://search.example.com/suggest?q={searchTerms}"
        )

        try preferences.upsertCustomSearchProvider(edited)
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBrowsingPreferences.self,
            from: encoded
        )

        XCTAssertEqual(decoded.searchProvider.id, .custom(id))
        XCTAssertEqual(decoded.searchProvider.title, "Example Search")
        XCTAssertEqual(decoded.customSearchProviders.map(\.id), [id])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(
            object["searchProvider"] as? String,
            "google",
            "An older Crest build must decode a safe built-in fallback when the new selection is custom."
        )
    }

    func testRemovingTheSelectedCustomProviderFallsBackToGoogle() throws {
        let custom = try BrowserCustomSearchProvider(
            name: "Kagi",
            searchURLTemplate: "https://kagi.com/search?q=%s"
        )
        var preferences = BrowserSpaceBrowsingPreferences.default
        try preferences.upsertCustomSearchProvider(custom)
        preferences.searchProvider = custom.provider

        preferences.removeCustomSearchProvider(id: custom.id)

        XCTAssertEqual(preferences.searchProvider, .google)
        XCTAssertFalse(
            preferences.availableSearchProviders.contains { $0.id == .custom(custom.id) }
        )
    }

    func testSearchTemplatesAcceptBothBrowserConventionsAndRejectAmbiguousOrUnsafeValues() throws {
        let percent = try BrowserCustomSearchProvider(
            name: "Percent",
            searchURLTemplate: "https://example.com/search/%s?source=crest"
        )
        let openSearch = try BrowserCustomSearchProvider(
            name: "OpenSearch",
            searchURLTemplate: "https://example.com/search?q={searchTerms}"
        )

        XCTAssertEqual(
            percent.provider.searchURL(for: "swift/ios")?.absoluteString,
            "https://example.com/search/swift%2Fios?source=crest"
        )
        XCTAssertEqual(
            openSearch.provider.searchURL(for: "swift+ios")?.absoluteString,
            "https://example.com/search?q=swift%2Bios"
        )

        for template in [
            "https://example.com/search",
            "https://example.com/?q=%s&again=%s",
            "https://example.com/?q=%s&again={searchTerms}",
            "http://example.com/?q=%s",
            "https://user:password@example.com/?q=%s",
            "https://%s.example.com/search",
            "https://example.com/search#q=%s",
            "https://localhost/search?q=%s",
            "https://example.com/search?token=secret&q=%s",
        ] {
            XCTAssertThrowsError(
                try BrowserCustomSearchProvider(
                    name: "Unsafe",
                    searchURLTemplate: template
                ),
                "Accepted unsafe or ambiguous template: \(template)"
            )
        }
        XCTAssertThrowsError(
            try BrowserCustomSearchProvider(
                name: "   ",
                searchURLTemplate: "https://example.com/?q=%s"
            )
        )
    }

    func testMalformedDecodedCustomProviderNeverBecomesExecutable() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000999")!
        let data = try JSONSerialization.data(withJSONObject: [
            "searchProvider": "google",
            "selectedSearchProviderID": "custom:\(id.uuidString.lowercased())",
            "customSearchProviders": [
                [
                    "id": id.uuidString,
                    "name": "Unsafe",
                    "searchURLTemplate": "http://127.0.0.1/search?q=%s",
                ]
            ],
            "currentTabCleanupPolicy": "after12Hours",
        ])

        let decoded = try JSONDecoder().decode(
            BrowserSpaceBrowsingPreferences.self,
            from: data
        )

        XCTAssertEqual(decoded.searchProvider, .google)
        XCTAssertEqual(decoded.availableSearchProviders, BrowserSearchProvider.allCases)
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
