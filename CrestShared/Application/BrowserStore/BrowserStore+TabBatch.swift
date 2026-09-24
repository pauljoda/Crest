import Foundation

extension BrowserStore {
    func prepareTabBatch(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction) throws
        -> (session: BrowserSession, result: BrowserTabBatchResult)
    {
        let prepared = try prepareOwnedTabBatch(request, action: action, at: .now)
        return (prepared.command.session, prepared.result)
    }

    private func prepareOwnedTabBatch(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction, at date: Date)
        throws -> (command: BrowserCoreSessionAuthority.PreparedChange, result: BrowserTabBatchResult) {
        guard let source = space(matching: request.assignment) else { throw BrowserTabBatchError.staleSelection }
        var observedIDs = Set(request.ids)
        if case .split(let target?, _) = action {
            observedIDs.insert(target)
            if let group = source.splitGroup(containing: target) {
                observedIDs.formUnion(source.splitGroupMembers(of: group).map(\.id))
            }
        }
        let arguments = BrowserCoreTabBatch.Arguments(
            request: request, action: action,
            follow: linkPreferences.followsTabsMovedToAnotherSpace,
            observations: copyObservations(for: observedIDs, in: source))
        return try family.prepareTabBatch(request, arguments: arguments, from: self, at: date)
    }

    func commitTabBatch(_ request: BrowserTabBatchRequest, action: BrowserTabBatchAction) throws {
        guard let source = space(matching: request.assignment) else { throw BrowserTabBatchError.staleSelection }
        let date = Date.now
        let accepted = try prepareOwnedTabBatch(request, action: action, at: date)
        try family.commitTabBatch(accepted.command,
            deletionReason: action == .delete ? .explicitDelete : .superseded, from: self, at: date)
        let prepared = (session: session, result: accepted.result)
        for pair in prepared.result.copies {
            guard let original = source.tabs.first(where: { $0.id == pair.source }),
                var copy = prepared.session.space(id: source.id)?.tabs.first(where: { $0.id == pair.copy }) else { continue }
            tabCopying?.prepareTabCopy(from: original, to: &copy, in: source)
        }
        if case .moveToSpace(let destination) = action, linkPreferences.followsTabsMovedToAnotherSpace,
            let id = selectedTabID(in: destination.spaceID) {
            pendingMovedTabActivation = BrowserTabRuntimeAssignment(tabID: id, spaceID: destination.spaceID,
                profileID: destination.profileID)
        } else { pendingMovedTabActivation = nil }
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
    }
}
