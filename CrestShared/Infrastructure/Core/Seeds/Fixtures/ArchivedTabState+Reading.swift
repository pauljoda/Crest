// Test fixtures: Debug builds, and CI's Release test build, which alone passes CREST_TEST_FIXTURES.
#if DEBUG || CREST_TEST_FIXTURES
    import Foundation

    extension ArchivedTabState.Seed {
        // MARK: - Variables

        /// The archived tab's identity.
        var id: UUID { tab.id }
    }
#endif
