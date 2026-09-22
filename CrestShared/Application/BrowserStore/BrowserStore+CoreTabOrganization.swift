import Foundation

extension BrowserStore {
    func moveSessionTab(_ id: TabID, in spaceID: SpaceID, to placement: TabPlacement,
        folderID: FolderID? = nil, before anchor: TabID? = nil, detachesFromSplit: Bool = false) -> Bool {
        return family.execute("tab.move", in: spaceID, arguments: [
            "tabId": id.rawValue.uuidString, "placement": placement.rawValue,
            "folderId": folderID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": anchor?.rawValue.uuidString as Any? ?? NSNull(), "detach": detachesFromSplit
        ], from: self, at: .now)?.changed ?? false
    }

    func copyObservations(for ids: Set<TabID>, in space: BrowserSpace) -> [[String: Any]] {
        space.tabs.filter { ids.contains($0.id) }.map { source in
            let observed = tabCopying?.sourceForTabCopy(source, in: space) ?? source
            return ["tabId": source.id.rawValue.uuidString, "title": observed.title,
                "url": observed.url?.absoluteString as Any? ?? NSNull()]
        }
    }

    func splitCopyObservations(source: TabID?, target: TabID, in space: BrowserSpace) -> [[String: Any]] {
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
        for pair in result.copies {
            guard let source = space.tabs.first(where: { $0.id.rawValue == pair.source }),
                var copy = result.space.tabs.first(where: { $0.id.rawValue == pair.copy }) else { continue }
            tabCopying?.prepareTabCopy(from: source, to: &copy, in: space)
        }
    }

    func persistSplitCommand(_ result: BrowserCoreSessionEditing.Result, from space: BrowserSpace) {
        prepareAcceptedCopies(result, from: space)
        persist(syncUrgency: .coalesced, scope: BrowserSessionSaveScope(writesCore: true,
            history: .nothing, favicons: .only(Set(result.copies.map { TabID(rawValue: $0.copy) }))))
    }
}
