import Foundation

extension BrowserStore {
    func moveSessionTab(
        _ id: TabID, in spaceID: SpaceID, to placement: TabPlacement,
        folderID: FolderID? = nil, before anchor: TabID? = nil, detachesFromSplit: Bool = false
    ) -> Bool {
        let arguments = BrowserSessionArguments.TabMove(
            tabId: id.rawValue, placement: placement, folderId: folderID?.rawValue, before: anchor?.rawValue,
            detach: detachesFromSplit)
        return family.execute(.tabMove, in: spaceID, arguments: arguments, from: self, at: .now)?.changed ?? false
    }

    func copyObservations(for ids: Set<TabID>, in space: BrowserSpace) -> [BrowserSessionArguments.CopyObservation] {
        space.tabs.filter { ids.contains($0.id) }.map { source in
            let observed = tabCopying?.sourceForTabCopy(source, in: space) ?? source
            return BrowserSessionArguments.CopyObservation(
                tabId: source.id.rawValue, title: observed.title, url: observed.url?.absoluteString)
        }
    }

    func splitCopyObservations(source: TabID?, target: TabID, in space: BrowserSpace)
        -> [BrowserSessionArguments.CopyObservation]
    {
        var ids: Set<TabID> = [target]
        if let source { ids.insert(source) }
        if let group = space.tabs.first(where: { $0.id == target })?.splitGroupID {
            ids.formUnion(space.splitGroupMembers(of: group).map(\.id))
        }
        return copyObservations(for: ids, in: space)
    }

    /// The core has accepted each copy's identity and visible URL/title. The
    /// adapter now prepares its opaque navigation history before pages mount.
    func prepareAcceptedCopies(_ result: BrowserCoreSessionEditing.Result, from space: BrowserSpace) {
        let copies = session.space(id: space.id)?.tabs ?? []
        for pair in result.copies {
            guard let source = space.tabs.first(where: { $0.id.rawValue == pair.source }),
                var copy = copies.first(where: { $0.id.rawValue == pair.copy })
            else { continue }
            tabCopying?.prepareTabCopy(from: source, to: &copy, in: space)
        }
    }

    func persistSplitCommand(_ result: BrowserCoreSessionEditing.Result, from space: BrowserSpace) {
        prepareAcceptedCopies(result, from: space)
        stageSync(urgency: .coalesced)
    }
}
