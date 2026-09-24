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

    /// What the pages of the tabs a split join may copy show now: the joining
    /// tab and the target's whole split.
    func splitSourcePages(source: TabID?, target: TabID, in space: BrowserSpace) -> [SourcePage] {
        var ids: Set<TabID> = [target]
        if let source { ids.insert(source) }
        if let group = space.tabs.first(where: { $0.id == target })?.splitGroupID {
            ids.formUnion(space.splitGroupMembers(of: group).map(\.id))
        }
        return copyObservations(for: ids, in: space).map {
            SourcePage(tabID: $0.tabId, address: $0.url, title: $0.title)
        }
    }

    /// The core has accepted each copy's identity and visible URL/title. The
    /// adapter now prepares its opaque navigation history before pages mount.
    func prepareAcceptedCopies(_ copies: [TabCopied], from space: BrowserSpace) {
        let tabs = session.space(id: space.id)?.tabs ?? []
        for pair in copies {
            guard let source = space.tabs.first(where: { $0.id.rawValue == pair.sourceTabID }),
                var copy = tabs.first(where: { $0.id.rawValue == pair.copyTabID })
            else { continue }
            tabCopying?.prepareTabCopy(from: source, to: &copy, in: space)
        }
    }

    /// Runs a join the window issued in `space`, and prepares the pages of
    /// the copies it made. Answers false when the core refused it.
    func sendSplitJoin(_ intent: some Intent, in space: BrowserSpace) -> Bool {
        guard let sent = family.perform(intent, from: self) else { return false }
        prepareAcceptedCopies(
            sent.changes.compactMap {
                guard case .tabCopied(let copied) = $0, copied.workspaceID == family.workspaceID else { return nil }
                return copied
            }, from: space)
        return true
    }
}
