import Foundation

extension BrowserStore {
    func addSpace() {
        session.addSpace()
        if isPrivateBrowsing, let spaceID = session.selectedSpace?.id {
            session.updateSpaceIdentity(
                spaceID,
                name: "Private \(session.spaces.count)",
                symbol: BrowserPrivateBrowsingAppearance.symbol,
                accent: .indigo
            )
            session.updateSpaceBranding(
                BrowserPrivateBrowsingAppearance.branding,
                in: spaceID
            )
            session.updateBrowsingPreferences(
                BrowserSpaceBrowsingPreferences(
                    searchProvider: .duckDuckGo,
                    currentTabCleanupPolicy: .never
                ),
                in: spaceID
            )
            session.updateCredentialPreferences(
                BrowserCredentialPreferences(
                    isEnabled: false,
                    syncsCrestPasswordsWithICloud: false,
                    alsoOffersSaveToSystemPasswords: false
                ),
                in: spaceID
            )
        }
        persist(scope: .core)
    }

    func deleteSpace(
        _ id: SpaceID,
        dataDeleter: any BrowserSpaceDataDeleting
    ) async throws {
        guard session.spaces.count > 1 else {
            throw BrowserSpaceDeletionError.cannotDeleteLastSpace
        }
        guard let space = session.space(id: id) else {
            throw BrowserSpaceDeletionError.missingSpace
        }
        guard family.beginDeletingSpace(id) else {
            throw BrowserSpaceDeletionError.alreadyDeleting
        }
        defer { family.finishDeletingSpace(id) }

        if session.selectedSpaceID == id,
           let index = session.spaces.firstIndex(where: { $0.id == id }) {
            let replacementIndex = index == session.spaces.index(before: session.spaces.endIndex)
                ? session.spaces.index(before: index)
                : session.spaces.index(after: index)
            session.selectSpace(session.spaces[replacementIndex].id)
            family.publish(session, from: self)
            persistence.save(session, scope: .core)
        }

        try await dataDeleter.deleteData(for: space)
        try await credentialVault.deleteAll(in: id)

        guard let currentSpace = session.space(id: id) else {
            throw BrowserSpaceDeletionError.missingSpace
        }
        guard currentSpace.profile.id == space.profile.id else {
            throw BrowserSpaceDeletionError.spaceChangedDuringDeletion
        }
        guard session.removeSpace(id) != nil else {
            throw BrowserSpaceDeletionError.cannotDeleteLastSpace
        }
        BrowserLinkPreferenceStore.shared.removeReferences(to: id)
        persist(deletionReason: .explicitDelete, scope: .core)
    }

    func importPortableArchive(_ imported: BrowserPortableImport) throws {
        guard !imported.spaces.isEmpty else { return }
        guard session.spaces.count + imported.spaces.count
                <= BrowserPortableArchive.maximumSpaceCount else {
            throw BrowserPortableArchiveError.spaceLimitExceeded(
                BrowserPortableArchive.maximumSpaceCount
            )
        }
        session.spaces.append(contentsOf: imported.spaces)
        session.selectedSpaceID = imported.spaces[0].id
        session.repairRuntimeIntegrity()
        // An import lands whole Spaces, with their history and their icons, so
        // this is one of the few mutations that really does rewrite everything.
        persist()
    }

    func commitReviewedImport(_ plan: BrowserImportReviewPlan) throws {
        session = try plan.preview(mergingInto: session)
        persist()
    }

    func commitManualSetup(_ plan: BrowserManualSetupPlan) throws {
        session = try plan.preview(mergingInto: session)
        persist()
    }

    func updateSpaceIdentity(
        _ spaceID: SpaceID,
        name: String,
        symbol: String,
        accent: SpaceAccent
    ) {
        guard session.space(id: spaceID) != nil else { return }
        session.updateSpaceIdentity(
            spaceID,
            name: name,
            symbol: symbol,
            accent: accent
        )
        persist(syncUrgency: .coalesced, scope: .core)
    }

    func updateSpaceBranding(
        _ branding: BrowserSpaceBranding,
        in spaceID: SpaceID
    ) {
        guard session.space(id: spaceID) != nil else { return }
        session.updateSpaceBranding(branding, in: spaceID)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    func setDefaultSpace(_ spaceID: SpaceID) {
        guard session.space(id: spaceID) != nil else { return }
        session.setDefaultSpace(spaceID)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    func updateSpaceAccessPolicy(
        _ accessPolicy: BrowserSpaceAccessPolicy,
        in spaceID: SpaceID
    ) {
        guard session.space(id: spaceID) != nil else { return }
        session.updateSpaceAccessPolicy(accessPolicy, in: spaceID)
        persist(syncUrgency: .immediate, scope: .core)
    }

    func moveSpaces(from source: IndexSet, to destination: Int) {
        session.moveSpaces(from: source, to: destination)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    func updateBrowsingPreferences(
        _ preferences: BrowserSpaceBrowsingPreferences,
        in spaceID: SpaceID
    ) {
        guard session.space(id: spaceID) != nil else { return }
        session.updateBrowsingPreferences(preferences, in: spaceID)
        persist(syncUrgency: .coalesced, scope: .core)
    }

}
