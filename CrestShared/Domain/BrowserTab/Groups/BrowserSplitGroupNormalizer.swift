import Foundation

enum BrowserSplitGroupNormalizer {
    /// Returns `tabs` with every `splitGroupID` that the group model cannot
    /// honour cleared, in one left-to-right pass.
    ///
    /// This function only ever *clears* membership. It never reorders tabs and
    /// never touches `positionModifiedAt`, because repair runs on merged and
    /// materialized state where a reorder would fight position-aware sync and a
    /// fresh timestamp would re-upload a change nobody made.
    ///
    /// Rules, applied in this order to each tab:
    /// 1. Pinned members are cleared — see `BrowserSplitGroupPolicy`.
    /// 2. Contiguity: the first maximal run of an ID keeps it; any later
    ///    re-occurrence of that same ID is cleared.
    /// 3. Uniformity: a run adopts its head member's `placement` and
    ///    `folderID`; a member that disagrees is cleared, which ends the run.
    /// 4. Cap: members past `BrowserSplitGroupPolicy.maximumMembers` within one
    ///    run are cleared.
    ///
    /// The rule this deliberately does **not** contain is singleton
    /// dissolution: a run of one keeps its ID. CloudKit batches arrive
    /// unordered, so a device that materializes 1-of-3 members first would,
    /// under a dissolution rule, strip that lone member's membership and then
    /// re-upload the strip to every other device — the same field-erasure
    /// failure the materializer's own comments warn about for folders. A
    /// sub-renderable run instead presents as a plain tab and silently
    /// reconstitutes when its siblings land. Dissolving a lone survivor is a
    /// decision only an explicit user mutation may take, which is why
    /// `BrowserSession.normalizeSplitGroupsAfterUserMutation(in:at:)` owns it.
    ///
    /// Idempotent: `normalized(normalized(x)) == normalized(x)`.
    static func normalized(_ tabs: [BrowserTab]) -> [BrowserTab] {
        var normalizedTabs = tabs
        var retiredIDs: Set<SplitGroupID> = []
        var runID: SplitGroupID?
        var runPlacement: TabPlacement = .current
        var runFolderID: FolderID?
        var runLength = 0

        for index in normalizedTabs.indices {
            let tab = normalizedTabs[index]
            guard let groupID = tab.splitGroupID else {
                if let runID { retiredIDs.insert(runID) }
                runID = nil
                runLength = 0
                continue
            }

            if !BrowserSplitGroupPolicy.allowsMembership(placement: tab.placement) {
                normalizedTabs[index].splitGroupID = nil
                if let runID { retiredIDs.insert(runID) }
                runID = nil
                runLength = 0
                continue
            }

            if groupID != runID {
                if let runID { retiredIDs.insert(runID) }
                runID = nil
                runLength = 0
                guard !retiredIDs.contains(groupID) else {
                    normalizedTabs[index].splitGroupID = nil
                    continue
                }
                runID = groupID
                runPlacement = tab.placement
                runFolderID = tab.folderID
                runLength = 1
                continue
            }

            guard tab.placement == runPlacement, tab.folderID == runFolderID else {
                normalizedTabs[index].splitGroupID = nil
                retiredIDs.insert(groupID)
                runID = nil
                runLength = 0
                continue
            }

            guard runLength < BrowserSplitGroupPolicy.maximumMembers else {
                // The run stays open so every further member past the cap is
                // trimmed too, rather than starting a second run of one ID.
                normalizedTabs[index].splitGroupID = nil
                continue
            }
            runLength += 1
        }

        return normalizedTabs
    }
}
