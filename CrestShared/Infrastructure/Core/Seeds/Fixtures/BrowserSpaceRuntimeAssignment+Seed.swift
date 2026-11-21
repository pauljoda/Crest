// Test fixtures: Debug builds, and CI's Release test build, which alone passes CREST_TEST_FIXTURES.
#if DEBUG || CREST_TEST_FIXTURES
    import Foundation

    extension BrowserSpaceRuntimeAssignment {
        // MARK: - Initializers

        /// Where a seeded Space lives: its identity and profile.
        init(space: SpaceState.Seed) {
            self.init(spaceID: space.id, profileID: space.profileID)
        }
    }
#endif
