import Foundation

/// The actions a window takes on the tabs and folders its sidebar selected.
/// Each is one intent whose rules the core owns: a menu asks `canSend` before
/// it offers one, and `send` shows the window what the core did.
extension BrowserStore {
    // MARK: - Actions - Batches

    /// Archives the selected open tabs.
    func closing(_ request: BrowserCapturedSelection) -> BrowserTabBatch {
        BrowserTabBatch(
            CloseTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection),
            reselection: .cleared, closesPages: true)
    }

    /// Deletes the selected tabs, saved and pinned ones included.
    func deleting(_ request: BrowserCapturedSelection) -> BrowserTabBatch {
        BrowserTabBatch(
            DeleteTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection),
            reselection: .cleared, closesPages: true)
    }

    /// Copies the selected tabs to the end of the open tabs.
    func duplicating(_ request: BrowserCapturedSelection) -> BrowserTabBatch {
        BrowserTabBatch(
            DuplicateTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection),
            reselection: .copies)
    }

    /// Combines the selected tabs in the split of `target`, or of the first
    /// selected tab, from member `index` on.
    func splitting(_ request: BrowserCapturedSelection, joining target: UUID? = nil, at index: Int? = nil)
        -> BrowserTabBatch
    {
        BrowserTabBatch(
            SplitTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection,
                targetTabID: target, index: index),
            reselection: .items)
    }

    /// Dissolves the splits the selected tabs belong to.
    func separatingSplits(_ request: BrowserCapturedSelection) -> BrowserTabBatch {
        BrowserTabBatch(
            SeparateSplits(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection),
            reselection: .items)
    }

    /// Keeps the selected tabs' pages loaded, or lets them unload.
    func keepingLoaded(_ request: BrowserCapturedSelection, _ keeps: Bool) -> BrowserTabBatch {
        BrowserTabBatch(
            KeepTabsLoaded(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection,
                keeps: keeps),
            reselection: .items)
    }

    /// Moves the selected tabs to another Space, which the core has the
    /// window follow them to when the person's link preferences say so.
    func moving(_ request: BrowserCapturedSelection, to destination: BrowserSpaceRuntimeAssignment) -> BrowserTabBatch {
        BrowserTabBatch(
            MoveTabsToSpace(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection,
                destinationSpaceID: destination.spaceID),
            reselection: .cleared, destination: destination)
    }

    /// Files the selection into `folder` or at the top level of `placement`'s
    /// section, before the tab `before` or the folder `beforeFolder`.
    func filing(
        _ request: BrowserCapturedSelection, _ placement: TabPlacement, folder: UUID? = nil, before: UUID? = nil,
        beforeFolder: UUID? = nil
    ) -> BrowserTabBatch {
        BrowserTabBatch(
            FileTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection,
                placement: placement, folderID: folder, beforeTabID: before,
                beforeFolderID: beforeFolder, leavesSplits: false),
            reselection: .items)
    }

    /// Files the selection into a new folder at the top level of `placement`'s section.
    func filingInNewFolder(_ request: BrowserCapturedSelection, in placement: TabPlacement) -> BrowserTabBatch {
        BrowserTabBatch(
            FolderTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection,
                placement: placement, title: Self.newFolderTitle),
            reselection: .items)
    }

    /// Files the open tab `tabID` and then the selection into a new folder in
    /// that tab's place.
    func filingInNewFolder(_ request: BrowserCapturedSelection, around tabID: UUID) -> BrowserTabBatch {
        BrowserTabBatch(
            FolderTabsAround(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: request.spaceID,
                selection: request.selection,
                tabID: tabID, title: Self.newFolderTitle),
            reselection: .items)
    }

    // MARK: - Actions - Sending

    /// Whether the core would accept the action now.
    func canSend(_ batch: BrowserTabBatch) -> Bool { family.canSend(batch.intent, from: self) }

    /// The rule that would refuse the action now, or nil when the core would take it.
    func refusal(of batch: BrowserTabBatch) -> Rejection? { family.refusal(of: batch.intent, from: self) }

    /// Sends the action, and then prepares the pages of the copies it made,
    /// selects what the action leaves selected, and remembers the tab the
    /// window follows to another Space. Answers the folder the action made,
    /// so a caller can open its name for editing, and nil when it made none.
    /// Throws the rule that refused it.
    @discardableResult
    func send(_ batch: BrowserTabBatch, for request: BrowserCapturedSelection) throws(Rejection) -> UUID? {
        let space = spaceModel(matching: request.assignment)
        let sources = space.map(BrowserTabCopySources.init)
        // The folders the Space held before the edit. The core names the folder
        // it makes, so the made one is the one that was not there. A Space this
        // window can no longer read leaves nothing to tell a made folder from a
        // moved one, and the edit still stands.
        let existingFolderIDs = space.map { Set($0.folders.models.map(\.id)) }
        let changes = try family.commit(batch.intent, from: self)
        let copies: [TabCopied] = changes.compactMap {
            guard case .tabCopied(let copied) = $0, copied.workspaceID == family.workspaceID else { return nil }
            return copied
        }
        if let sources { prepareAcceptedCopies(copies, from: sources) }
        // The window followed the tabs when the core moved it to their Space.
        pendingMovedTabActivation = batch.destination.flatMap { destination in
            guard selectedSpaceID == destination.spaceID else { return nil }
            return selectedTabID(in: destination.spaceID).map {
                BrowserTabRuntimeAssignment(tabID: $0, spaceID: destination.spaceID, profileID: destination.profileID)
            }
        }
        batch.reselection.apply(tabMultiSelection, copies, request)
        guard let existingFolderIDs else { return nil }
        return changes.compactMap { change -> UUID? in
            guard case .foldersChanged(let folders) = change,
                folders.workspaceID == family.workspaceID, folders.spaceID == request.spaceID
            else { return nil }
            return folders.updated.first { !existingFolderIDs.contains($0.id) }?.id
        }.first
    }
}
