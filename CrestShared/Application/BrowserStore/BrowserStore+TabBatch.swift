import Foundation

extension BrowserStore {
    func prepareTabBatch(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction) throws
        -> (session: BrowserSession, result: BrowserTabBatchResult)
    {
        guard session.selectedSpaceID == request.assignment.spaceID,
            !deletingSpaceIDs.contains(request.assignment.spaceID)
        else { throw BrowserTabBatchError.staleSelection }
        let source = try request.validate(in: session)
        if case .moveToSpace(let destination) = action, deletingSpaceIDs.contains(destination.spaceID) {
            throw BrowserTabBatchError.staleSelection
        }
        var history = tabSelectionHistory
        let fallback = source.selectedTabID.flatMap {
            history.fallbackTabID(
                afterDismissing: $0, in: source.id,
                availableTabIDs: Set(source.tabs.map(\.id)).subtracting(request.ids))
        }
        var draft = session
        let result = try draft.applyTabBatch(request, action: action, fallbackTabID: fallback)
        return (draft, result)
    }

    func commitTabBatch(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction) throws {
        var prepared = try prepareTabBatch(request, action: action)
        guard let source = space(matching: request.assignment),
            let index = prepared.session.spaces.firstIndex(where: { $0.id == source.id })
        else { throw BrowserTabBatchError.staleSelection }
        for pair in prepared.result.copies {
            guard let original = source.tabs.first(where: { $0.id == pair.source }),
                let copyIndex = prepared.session.spaces[index].tabs.firstIndex(where: { $0.id == pair.copy })
            else { continue }
            tabCopying?.prepareTabCopy(from: original, to: &prepared.session.spaces[index].tabs[copyIndex], in: source)
        }
        var activation: BrowserTabRuntimeAssignment?
        if case .moveToSpace(let destination) = action, linkPreferences.followsTabsMovedToAnotherSpace {
            let id = source.selectedTabID.flatMap { request.ids.contains($0) ? $0 : nil } ?? request.ids[0]
            prepared.session.selectSpace(destination.spaceID)
            prepared.session.selectTab(id)
            activation = BrowserTabRuntimeAssignment(
                tabID: id, spaceID: destination.spaceID, profileID: destination.profileID)
        }
        session = prepared.session
        pendingMovedTabActivation = activation
        switch action {
        case .close, .delete, .moveToSpace: tabMultiSelection.clear()
        case .duplicate:
            tabMultiSelection.selectAll(units: prepared.result.copies.map { [$0.copy] })
        default:
            let copies = Dictionary(uniqueKeysWithValues: prepared.result.copies.map { ($0.source, $0.copy) })
            tabMultiSelection.selectAll(
                units: request.rootItems.map { item in
                    if case .tab(let id) = item { return [.tab(copies[id] ?? id)] }
                    return [item]
                })
        }
        persist(
            syncUrgency: .coalesced,
            scope: BrowserSessionSaveScope(
                writesCore: true, history: .nothing,
                favicons: .only(Set(prepared.result.copies.map(\.copy)))))
    }
}
