import Foundation

// MARK: - Spaces and Import

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
            let index = session.spaces.firstIndex(where: { $0.id == id })
        {
            let replacementIndex =
                index == session.spaces.index(before: session.spaces.endIndex)
                ? session.spaces.index(before: index)
                : session.spaces.index(after: index)
            session.selectSpace(session.spaces[replacementIndex].id)
            let revision = family.publish(session, from: self)
            syncCoordinator?.advanceStoreRevision(to: revision)
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
        guard
            session.spaces.count + imported.spaces.count
                <= BrowserPortableArchive.maximumSpaceCount
        else {
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

// MARK: - Folders

extension BrowserStore {
    @discardableResult
    func setSavedTabsExpanded(
        _ isExpanded: Bool,
        in spaceID: SpaceID
    ) -> Bool {
        guard session.setSavedTabsExpanded(isExpanded, in: spaceID) else {
            return false
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setSavedTabsExpanded(
        _ isExpanded: Bool,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return setSavedTabsExpanded(isExpanded, in: assignment.spaceID)
    }

    @discardableResult
    func addFolder(
        title: String = "New Folder",
        color: BrowserSpaceBrandColor = .folderDefault,
        parentID: FolderID? = nil,
        in spaceID: SpaceID
    ) -> FolderID? {
        guard
            let folderID = session.addFolder(
                title: title,
                color: color,
                parentID: parentID,
                in: spaceID
            )
        else { return nil }
        persist(scope: .core)
        return folderID
    }

    @discardableResult
    func addFolder(
        title: String = "New Folder",
        color: BrowserSpaceBrandColor = .folderDefault,
        parentID: FolderID? = nil,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> FolderID? {
        guard space(matching: assignment) != nil else { return nil }
        return addFolder(
            title: title,
            color: color,
            parentID: parentID,
            in: assignment.spaceID
        )
    }

    @discardableResult
    func renameFolder(_ folderID: FolderID, in spaceID: SpaceID, title: String) -> Bool {
        guard session.renameFolder(folderID, in: spaceID, title: title) else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func renameFolder(
        _ folderID: FolderID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        title: String
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.folders.contains(where: { $0.id == folderID })
        else { return false }
        return renameFolder(folderID, in: assignment.spaceID, title: title)
    }

    @discardableResult
    func setFolderColor(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        color: BrowserSpaceBrandColor
    ) -> Bool {
        guard session.setFolderColor(folderID, in: spaceID, color: color) else {
            return false
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setFolderColor(
        _ folderID: FolderID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        color: BrowserSpaceBrandColor
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.folders.contains(where: { $0.id == folderID })
        else { return false }
        return setFolderColor(
            folderID,
            in: assignment.spaceID,
            color: color
        )
    }

    @discardableResult
    func setFolderCollapsed(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        isCollapsed: Bool
    ) -> Bool {
        guard
            session.setFolderCollapsed(
                folderID,
                in: spaceID,
                isCollapsed: isCollapsed
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setFolderCollapsed(
        _ folderID: FolderID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isCollapsed: Bool
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.folders.contains(where: { $0.id == folderID })
        else { return false }
        return setFolderCollapsed(
            folderID,
            in: assignment.spaceID,
            isCollapsed: isCollapsed
        )
    }

    func canMoveFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        into parentID: FolderID?
    ) -> Bool {
        session.canMoveFolder(folderID, in: spaceID, into: parentID)
    }

    func canMoveFolder(
        _ folderID: FolderID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        into parentID: FolderID?
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.folders.contains(where: { $0.id == folderID })
        else { return false }
        return canMoveFolder(
            folderID,
            in: assignment.spaceID,
            into: parentID
        )
    }

    @discardableResult
    func moveFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        into parentID: FolderID?,
        before siblingID: FolderID? = nil
    ) -> Bool {
        guard
            session.moveFolder(
                folderID,
                in: spaceID,
                into: parentID,
                before: siblingID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func moveFolder(
        _ folderID: FolderID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        into parentID: FolderID?,
        before siblingID: FolderID? = nil
    ) -> Bool {
        guard let space = space(matching: assignment),
            siblingID == nil
                || space.folders.contains(where: {
                    $0.id == siblingID && $0.parentID == parentID
                }),
            canMoveFolder(
                folderID,
                matching: assignment,
                into: parentID
            )
        else { return false }
        return moveFolder(
            folderID,
            in: assignment.spaceID,
            into: parentID,
            before: siblingID
        )
    }

    @discardableResult
    func moveFolder(
        _ item: BrowserFolderDragItem,
        matching destinationAssignment: BrowserSpaceRuntimeAssignment,
        into parentID: FolderID?,
        before siblingID: FolderID? = nil
    ) -> Bool {
        let sourceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: item.spaceID,
            profileID: item.profileID
        )
        guard sourceAssignment == destinationAssignment else { return false }
        return moveFolder(
            item.folderID,
            matching: destinationAssignment,
            into: parentID,
            before: siblingID
        )
    }

    @discardableResult
    func deleteFolder(_ folderID: FolderID, in spaceID: SpaceID) -> Bool {
        guard session.deleteFolder(folderID, in: spaceID) else { return false }
        persist(deletionReason: .explicitDelete, scope: .core)
        return true
    }

    @discardableResult
    func deleteFolder(
        _ folderID: FolderID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.folders.contains(where: { $0.id == folderID })
        else { return false }
        return deleteFolder(folderID, in: assignment.spaceID)
    }

}
