import Foundation

// MARK: - Spaces and Import

extension BrowserStore {
    /// Composition wires the app's one access authority into every store family
    /// it owns, including private browsing.
    func attachSpaceAccess(_ controller: BrowserSpaceAccessController) {
        family.attachSpaceAccess(controller)
    }

    func addSpace() {
        guard spaceCommandOwner(.spaceCreate) === self else { return }
        guard createCoreSpace() else { return }
        persist(scope: .core)
    }

    func deleteSpace(
        _ id: SpaceID,
        dataDeleter: any BrowserSpaceDataDeleting
    ) async throws {
        guard spaceCommandOwner(.spaceDeletionBegin, in: id) === self else {
            throw BrowserSpaceDeletionError.borrowedProfile
        }
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

        let operationID = session.spaceDeletions?.first(where: { $0.spaceID == id })?.operationID ?? UUID()
        try family.executeSpaceDurably(
            .spaceDeletionBegin, in: id, arguments: BrowserSessionArguments.SpaceDeletion(operationID: operationID),
            from: self)

        try await dataDeleter.deleteData(for: space)
        try await credentialVault.deleteAll(in: id)

        guard let currentSpace = session.space(id: id) else {
            throw BrowserSpaceDeletionError.missingSpace
        }
        guard currentSpace.profile.id == space.profile.id else {
            throw BrowserSpaceDeletionError.spaceChangedDuringDeletion
        }
        try family.executeSpaceDurably(
            .spaceRemove, in: id, arguments: BrowserSessionArguments.SpaceDeletion(operationID: operationID),
            deletionReason: .explicitDelete, from: self)
        BrowserLinkPreferenceStore.shared.removeReferences(to: id)
    }

    func resumePendingSpaceDeletions(dataDeleter: any BrowserSpaceDataDeleting) async {
        var attempted: Set<SpaceID> = []
        while let intent = (session.spaceDeletions ?? []).first(where: {
            !attempted.contains($0.spaceID) && !family.isActivelyDeletingSpace($0.spaceID)
        }) {
            attempted.insert(intent.spaceID)
            do { try await deleteSpace(intent.spaceID, dataDeleter: dataDeleter) }
            catch { localSyncErrorDescription = "Space cleanup needs another attempt: \(error.localizedDescription)" }
        }
    }

    func importPortableArchive(_ imported: BrowserPortableImport) throws {
        guard !imported.spaces.isEmpty else { return }
        try family.importWorkspace(BrowserCoreWorkspaceImport.portable(imported.spaces), from: self)
    }

    func commitReviewedImport(_ plan: BrowserImportReviewPlan) throws {
        try family.importWorkspace(BrowserCoreWorkspaceImport.review(plan), from: self)
    }

    func commitManualSetup(_ plan: BrowserManualSetupPlan) throws {
        try family.importWorkspace(BrowserCoreWorkspaceImport.manual(plan), from: self)
    }

    func updateSpaceIdentity(
        _ spaceID: SpaceID,
        name: String,
        symbol: String,
        accent: SpaceAccent
    ) {
        guard let owner = spaceCommandOwner(.spaceIdentity, in: spaceID),
            owner.session.space(id: spaceID) != nil else { return }
        guard
            owner.family.executeSpace(
                .spaceIdentity, in: spaceID,
                arguments: BrowserSessionArguments.SpaceIdentity(name: name, symbol: symbol, accent: accent),
                from: owner)
        else { return }
        owner.persist(syncUrgency: .coalesced, scope: .core)
    }

    func updateSpaceBranding(
        _ branding: BrowserSpaceBranding,
        in spaceID: SpaceID
    ) {
        guard let owner = spaceCommandOwner(.spaceBranding, in: spaceID),
            owner.session.space(id: spaceID) != nil else { return }
        // The command applies the core's branding rules to the stored record.
        guard owner.setCoreSpaceValue(.spaceBranding, branding, in: spaceID) else { return }
        owner.persist(syncUrgency: .coalesced, scope: .core)
    }

    func setDefaultSpace(_ spaceID: SpaceID) {
        guard let owner = spaceCommandOwner(.spaceDefault, in: spaceID),
            owner.session.space(id: spaceID) != nil else { return }
        guard owner.family.executeSpace(.spaceDefault, in: spaceID, arguments: BrowserCoreNoArguments(), from: owner)
        else { return }
        owner.persist(syncUrgency: .coalesced, scope: .core)
    }

    func updateSpaceAccessPolicy(
        _ accessPolicy: BrowserSpaceAccessPolicy,
        in spaceID: SpaceID
    ) {
        guard let owner = spaceCommandOwner(.spaceAccess, in: spaceID),
            owner.session.space(id: spaceID) != nil else { return }
        guard owner.setCoreSpaceValue(.spaceAccess, accessPolicy, in: spaceID) else { return }
        owner.persist(syncUrgency: .immediate, scope: .core)
    }

    func moveSpaces(from source: IndexSet, to destination: Int) {
        guard spaceCommandOwner(.spaceReorder) === self else { return }
        guard
            family.executeSpace(
                .spaceReorder,
                arguments: BrowserSessionArguments.SpaceReorder(offsets: Array(source), destination: destination),
                from: self)
        else { return }
        persist(syncUrgency: .coalesced, scope: .core)
    }

    func updateBrowsingPreferences(
        _ preferences: BrowserSpaceBrowsingPreferences,
        in spaceID: SpaceID
    ) {
        guard let owner = spaceCommandOwner(.spaceBrowsingPreferences, in: spaceID),
            owner.session.space(id: spaceID) != nil else { return }
        guard owner.setCoreSpaceValue(.spaceBrowsingPreferences, preferences, in: spaceID) else { return }
        owner.persist(syncUrgency: .coalesced, scope: .core)
    }

    /// Saves a custom search engine through the core, which validates it,
    /// rejects duplicate names and the Space's engine limit, and optionally
    /// selects it. Throws the rule the engine breaks.
    func upsertCustomSearchProvider(
        _ provider: BrowserCustomSearchProvider,
        selects: Bool,
        in spaceID: SpaceID
    ) throws {
        guard let owner = spaceCommandOwner(.spaceSearchProviderUpsert, in: spaceID),
            let space = owner.session.space(id: spaceID) else { return }
        let admission = CustomSearchEngineAdmission(
            engine: provider.engine, existing: space.browsingPreferences.customSearchProviders.map(\.engine))
        let admitted: BrowserCustomSearchProvider
        do {
            admitted = BrowserCustomSearchProvider(try core.query(admission))
        } catch {
            throw BrowserCustomSearchProviderError(error)
        }
        // The command re-applies the same rule against the accepted record; an
        // unchanged save reports no change rather than an error.
        guard
            owner.family.executeSpace(
                .spaceSearchProviderUpsert, in: spaceID,
                arguments: BrowserSessionArguments.SearchProviderUpsert(
                    provider: BrowserCoreSearchProviderRecord(admitted), selects: selects),
                from: owner)
        else { return }
        owner.persist(syncUrgency: .coalesced, scope: .core)
    }

    /// Removes a custom search engine; the core selects Google if it was chosen.
    func removeCustomSearchProvider(id: UUID, in spaceID: SpaceID) {
        guard let owner = spaceCommandOwner(.spaceSearchProviderRemove, in: spaceID),
            owner.session.space(id: spaceID) != nil else { return }
        guard
            owner.family.executeSpace(
                .spaceSearchProviderRemove, in: spaceID,
                arguments: BrowserSessionArguments.SearchProviderRemove(id: id.coreIdentifier), from: owner)
        else { return }
        owner.persist(syncUrgency: .coalesced, scope: .core)
    }

}

// MARK: - Folders

extension BrowserStore {
    @discardableResult
    func setSavedTabsExpanded(
        _ isExpanded: Bool,
        in spaceID: SpaceID
    ) -> Bool {
        guard let owner = spaceCommandOwner(.spaceSavedExpansion, in: spaceID),
            owner.setCoreSpaceValue(.spaceSavedExpansion, isExpanded, in: spaceID) else { return false }
        owner.persist(syncUrgency: .coalesced, scope: .core)
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
        let folderID = FolderID()
        let arguments = BrowserSessionArguments.FolderCreate(
            folderId: folderID.rawValue, title: title, placement: .saved, parentId: parentID?.rawValue, color: color,
            symbol: "folder")
        guard family.execute(.folderCreate, in: spaceID, arguments: arguments, from: self, at: .now) != nil else {
            return nil
        }
        persist(scope: .core)
        return folderID
    }

    /// Whether a folder may be created inside `parentID`. The core answers
    /// with its folder count and depth limits.
    func canAddFolder(inside parentID: FolderID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return family.accepts(
            .folderCreate, in: assignment.spaceID,
            arguments: BrowserSessionArguments.FolderCreate(
                folderId: UUID(), title: nil, placement: .saved, parentId: parentID.rawValue),
            from: self)
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
        guard renameSessionFolder(folderID, in: spaceID, title: title) else { return false }
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
        guard
            family.execute(
                .folderColor, in: spaceID,
                arguments: BrowserSessionArguments.FolderValue(folderId: folderID.rawValue, value: color),
                from: self, at: .now)?.changed == true
        else { return false }
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
    func setFolderSymbol(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        symbol: String
    ) -> Bool {
        guard
            family.execute(
                .folderSymbol, in: spaceID,
                arguments: BrowserSessionArguments.FolderValue(folderId: folderID.rawValue, value: symbol),
                from: self, at: .now)?.changed == true
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setFolderSymbol(
        _ folderID: FolderID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        symbol: String
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.folders.contains(where: { $0.id == folderID })
        else { return false }
        return setFolderSymbol(
            folderID,
            in: assignment.spaceID,
            symbol: symbol
        )
    }

    @discardableResult
    func setFolderCollapsed(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        isCollapsed: Bool
    ) -> Bool {
        guard
            collapseSessionFolder(
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

    /// Whether a folder may move under `parentID`. The core's folder rules
    /// answer (no cycles, the depth limit including the moving subtree).
    func canMoveFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        into parentID: FolderID?
    ) -> Bool {
        guard !deletingSpaceIDs.contains(spaceID) else { return false }
        return family.accepts(
            .folderMove, in: spaceID,
            arguments: BrowserSessionArguments.FolderMove(
                folderId: folderID.rawValue, parentId: parentID?.rawValue, beforeFolderId: nil, before: nil,
                placement: nil),
            from: self)
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
            moveSessionFolder(
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
        guard deleteSessionFolder(folderID, in: spaceID) else { return false }
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
