import Foundation

// MARK: - Spaces and Import

extension BrowserStore {
    /// Composition wires the app's one access authority into every store family
    /// it owns, including private browsing.
    func attachSpaceAccess(_ controller: BrowserSpaceAccessController) {
        family.attachSpaceAccess(controller)
    }

    func addSpace() {
        family.send(
            CreateSpace(workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: UUID()), from: self,
            failure: "Core Space command failed")
    }

    /// Deletes a Space in two steps the core saves before each returns: the
    /// deletion begins, the platform erases the profile's data and its
    /// passwords, then the Space goes. A relaunch resumes a deletion that
    /// began, with the operation it recorded. Throws the rule the core applied
    /// or why erasing failed; the Space is then kept.
    func deleteSpace(
        _ id: SpaceID,
        dataDeleter: any BrowserSpaceDataDeleting
    ) async throws {
        guard let space = session.space(id: id) else {
            throw BrowserSpaceDeletionError.missingSpace
        }
        guard family.beginDeletingSpace(id) else {
            throw BrowserSpaceDeletionError.alreadyDeleting
        }
        defer { family.finishDeletingSpace(id) }

        let operationID = session.spaceDeletions?.first(where: { $0.spaceID == id })?.operationID ?? UUID()
        try family.commit(
            BeginDeletingSpace(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: id.rawValue,
                operationID: operationID),
            from: self)

        try await dataDeleter.deleteData(for: space)
        try await credentialVault.deleteAll(in: id)

        try family.commit(
            FinishDeletingSpace(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: id.rawValue,
                operationID: operationID),
            from: self)
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
        sendSpaceSettings(
            SetSpaceIdentity(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID.rawValue, name: name,
                symbol: symbol, accent: accent))
    }

    /// The core applies its branding rules to the look before it keeps it.
    func updateSpaceBranding(
        _ branding: BrowserSpaceBranding,
        in spaceID: SpaceID
    ) {
        sendSpaceSettings(
            SetSpaceBranding(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID.rawValue,
                branding: branding.core))
    }

    func setDefaultSpace(_ spaceID: SpaceID) {
        sendSpaceSettings(
            SetDefaultSpace(workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID.rawValue))
    }

    func updateSpaceAccessPolicy(
        _ accessPolicy: BrowserSpaceAccessPolicy,
        in spaceID: SpaceID
    ) {
        sendSpaceSettings(
            SetSpaceAccess(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID.rawValue,
                policy: SpaceAccessPolicy(copyTerm: accessPolicy) ?? .deviceOwnerAuthentication))
    }

    /// Sends an intent about a Space's settings to the workspace that owns
    /// the Space's profile: this one, or the one a borrowed workspace borrows
    /// its Space from. Answers whether the session changed.
    @discardableResult
    func sendSpaceSettings(_ intent: some Intent) -> Bool {
        let owner = profileSettingsBrowser
        return owner.family.send(intent, from: owner, failure: "Core Space command failed")
    }

    func moveSpaces(from source: IndexSet, to destination: Int) {
        var order = session.spaces.map(\.id.rawValue)
        order.move(fromOffsets: source, toOffset: destination)
        family.send(
            ReorderSpaces(workspaceID: family.workspaceID, spaceIDs: order), from: self,
            failure: "Core Space command failed")
    }

    func updateBrowsingPreferences(
        _ preferences: BrowserSpaceBrowsingPreferences,
        in spaceID: SpaceID
    ) {
        guard let owner = spaceCommandOwner(.spaceBrowsingPreferences, in: spaceID),
            owner.session.space(id: spaceID) != nil else { return }
        guard owner.setCoreSpaceValue(.spaceBrowsingPreferences, preferences, in: spaceID) else { return }
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
    }

}

// MARK: - Folders

extension BrowserStore {
    @discardableResult
    func setSavedTabsExpanded(
        _ isExpanded: Bool,
        in spaceID: SpaceID
    ) -> Bool {
        sendSpaceSettings(
            ExpandSavedTabs(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID.rawValue,
                isExpanded: isExpanded))
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
        guard
            family.send(
                CreateFolder(
                    workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: folderID.rawValue,
                    placement: .saved, parentID: parentID?.rawValue, title: title, color: color.core, symbol: "folder",
                    tabIDs: [], leavesSplits: false),
                from: self)
        else { return nil }
        return folderID
    }

    /// Whether a folder may be created inside `parentID`. The core answers
    /// with its folder count and depth limits.
    func canAddFolder(inside parentID: FolderID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return family.canSend(
            CreateFolder(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID.rawValue, folderID: UUID(),
                placement: .saved, parentID: parentID.rawValue, title: nil, color: nil, symbol: nil, tabIDs: [],
                leavesSplits: false),
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
        family.send(
            SetFolderColor(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: folderID.rawValue,
                color: color.core),
            from: self)
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
        family.send(
            SetFolderSymbol(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: folderID.rawValue,
                symbol: symbol),
            from: self)
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
        return family.canSend(
            MoveFolder(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: folderID.rawValue, placement: nil,
                parentID: parentID?.rawValue, beforeFolderID: nil, beforeTabID: nil),
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
