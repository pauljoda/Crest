// Test fixtures: Debug builds, and CI's Release test build, which alone passes CREST_TEST_FIXTURES.
#if DEBUG || CREST_TEST_FIXTURES
    import Foundation

    extension BrowserStore {
        /// Unlocks the seeded Space `space` in the core, as the device owner's
        /// authentication does, for a test that shows or edits a protected
        /// Space. The core keeps every protected Space locked until then,
        /// whatever the views believe.
        func unlockForTesting(_ space: SpaceState.Seed) {
            let request = UUID()
            _ = try? core.send(
                BeginUnlockingSpace(workspaceID: family.workspaceID, spaceID: space.id, requestID: request))
            _ = try? core.send(FinishUnlockingSpace(spaceID: space.id, requestID: request, authenticated: true))
        }

        /// Whether this window's session is the one whose journal syncs: only
        /// the session the core keeps in its file does.
        var syncsSession: Bool {
            core.state.syncJournal?.workspaceID == family.workspaceID
        }
    }

    extension UUID {
        /// A fixed identity for a test, spelled by `value` in its last digits.
        init(fixed value: Int) {
            self.init(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
        }
    }
#endif
