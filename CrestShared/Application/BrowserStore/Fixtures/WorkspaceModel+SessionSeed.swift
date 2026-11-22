// Test fixtures: Debug builds, and CI's Release test build, which alone passes CREST_TEST_FIXTURES.
#if DEBUG || CREST_TEST_FIXTURES
    import Foundation

    extension WorkspaceModel {
        /// The session this workspace holds now, as a seed. The read model
        /// keeps no disposable seed's marker, so the seed carries none.
        var sessionSeed: SessionState.Seed {
            SessionState.Seed(
                spaces: spaces.models.map(\.value.seed), defaultSpaceID: defaultSpaceID, disposableSeedMarker: nil,
                spaceDeletions: spaceDeletions.map(\.seed), appPreferences: appPreferences)
        }
    }
#endif
