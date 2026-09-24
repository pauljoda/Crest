import Foundation

/// The actions a window takes on the tabs and folders its sidebar selected.
/// Each is one intent whose rules the core owns: a menu asks `canSend` before
/// it offers one, and `send` shows the window what the core did.
extension BrowserStore {
    // MARK: - Actions - Batches

    /// Archives the selected open tabs.
    func closing(_ request: BrowserTabBatchRequest) -> BrowserTabBatch {
        BrowserTabBatch(
            CloseTabs(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core),
            reselection: .cleared, closesPages: true)
    }

    /// Deletes the selected tabs, saved and pinned ones included.
    func deleting(_ request: BrowserTabBatchRequest) -> BrowserTabBatch {
        BrowserTabBatch(
            DeleteTabs(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core),
            reselection: .cleared, closesPages: true)
    }

    /// Copies the selected tabs to the end of the open tabs.
    func duplicating(_ request: BrowserTabBatchRequest) -> BrowserTabBatch {
        BrowserTabBatch(
            DuplicateTabs(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core),
            reselection: .copies)
    }

    /// Combines the selected tabs in the split of `target`, or of the first
    /// selected tab, from member `index` on.
    func splitting(_ request: BrowserTabBatchRequest, joining target: TabID? = nil, at index: Int? = nil)
        -> BrowserTabBatch
    {
        BrowserTabBatch(
            SplitTabs(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core,
                targetTabID: target?.rawValue, index: index),
            reselection: .items)
    }

    /// Dissolves the splits the selected tabs belong to.
    func separatingSplits(_ request: BrowserTabBatchRequest) -> BrowserTabBatch {
        BrowserTabBatch(
            SeparateSplits(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core),
            reselection: .items)
    }

    /// Keeps the selected tabs' pages loaded, or lets them unload.
    func keepingLoaded(_ request: BrowserTabBatchRequest, _ keeps: Bool) -> BrowserTabBatch {
        BrowserTabBatch(
            KeepTabsLoaded(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core,
                keeps: keeps),
            reselection: .items)
    }

    /// Moves the selected tabs to another Space, which the window follows
    /// them to when the person's link preferences say so.
    func moving(_ request: BrowserTabBatchRequest, to destination: BrowserSpaceRuntimeAssignment) -> BrowserTabBatch {
        let follows = linkPreferences.followsTabsMovedToAnotherSpace
        return BrowserTabBatch(
            MoveTabsToSpace(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core,
                destinationSpaceID: destination.spaceID.rawValue, follows: follows),
            reselection: .cleared, following: follows ? destination : nil)
    }

    /// Files the selection into `folder` or at the top level of `placement`'s
    /// section, before the tab `before` or the folder `beforeFolder`.
    func filing(
        _ request: BrowserTabBatchRequest, _ placement: TabPlacement, folder: FolderID? = nil, before: TabID? = nil,
        beforeFolder: FolderID? = nil
    ) -> BrowserTabBatch {
        BrowserTabBatch(
            FileTabs(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core,
                placement: placement, folderID: folder?.rawValue, beforeTabID: before?.rawValue,
                beforeFolderID: beforeFolder?.rawValue, leavesSplits: false),
            reselection: .items)
    }

    /// Files the selection into a new folder at the top level of `placement`'s section.
    func filingInNewFolder(_ request: BrowserTabBatchRequest, in placement: TabPlacement) -> BrowserTabBatch {
        BrowserTabBatch(
            FolderTabs(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core,
                placement: placement),
            reselection: .items)
    }

    /// Files the open tab `tabID` and then the selection into a new folder in
    /// that tab's place.
    func filingInNewFolder(_ request: BrowserTabBatchRequest, around tabID: TabID) -> BrowserTabBatch {
        BrowserTabBatch(
            FolderTabsAround(
                workspaceID: family.workspaceID, windowID: windowID.rawValue, spaceID: request.space,
                selection: request.core,
                tabID: tabID.rawValue),
            reselection: .items)
    }

    // MARK: - Actions - Sending

    /// Whether the core would accept the action now.
    func canSend(_ batch: BrowserTabBatch) -> Bool { family.canSend(batch.intent, from: self) }

    /// The rule that would refuse the action now, or nil when the core would take it.
    func refusal(of batch: BrowserTabBatch) -> Rejection? { family.refusal(of: batch.intent, from: self) }

    /// Sends the action, and then prepares the pages of the copies it made,
    /// selects what the action leaves selected, and remembers the tab the
    /// window follows to another Space. Throws the rule that refused it.
    func send(_ batch: BrowserTabBatch, for request: BrowserTabBatchRequest) throws(Rejection) {
        let source = space(matching: request.assignment)
        let changes = try family.commit(batch.intent, from: self)
        let copies: [TabCopied] = changes.compactMap {
            guard case .tabCopied(let copied) = $0, copied.workspaceID == family.workspaceID else { return nil }
            return copied
        }
        if let source { prepareAcceptedCopies(copies, from: source) }
        pendingMovedTabActivation = batch.following.flatMap { destination in
            selectedTabID(in: destination.spaceID).map {
                BrowserTabRuntimeAssignment(tabID: $0, spaceID: destination.spaceID, profileID: destination.profileID)
            }
        }
        switch batch.reselection {
        case .cleared: tabMultiSelection.clear()
        case .copies: tabMultiSelection.selectAll(units: copies.map { [.tab(TabID(rawValue: $0.copyTabID))] })
        case .items:
            let copied = Dictionary(uniqueKeysWithValues: copies.map { ($0.sourceTabID, $0.copyTabID) })
            tabMultiSelection.selectAll(
                units: request.rootItems.map { item in
                    guard case .tab(let id) = item, let copy = copied[id.rawValue] else { return [item] }
                    return [.tab(TabID(rawValue: copy))]
                })
        }
    }
}

extension BrowserTabBatchRequest {
    /// The Space the selection was made in, as intents name it.
    fileprivate var space: UUID { assignment.spaceID.rawValue }
}
