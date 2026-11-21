// Test fixtures: Debug builds, and CI's Release test build, which alone passes CREST_TEST_FIXTURES.
#if DEBUG || CREST_TEST_FIXTURES
    import Foundation

    extension TabState.Seed {
        // MARK: - Variables

        /// The address the tab shows, as the platform reads addresses.
        var address: URL? { url.flatMap(URL.init(string:)) }
    }
#endif
