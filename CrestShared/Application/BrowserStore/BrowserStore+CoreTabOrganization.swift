import Foundation

extension BrowserStore {
    /// Moves a tab within its Space, and answers whether it moved. A split
    /// member leaves its split when `detachesFromSplit`; the core refuses to
    /// pin one that does not.
    func moveSessionTab(
        _ id: TabID, in spaceID: SpaceID, to placement: TabPlacement,
        folderID: FolderID? = nil, before anchor: TabID? = nil, detachesFromSplit: Bool = false
    ) -> Bool {
        family.send(
            MoveTab(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, tabID: id.rawValue, placement: placement,
                folderID: folderID?.rawValue, beforeTabID: anchor?.rawValue, leavesSplit: detachesFromSplit),
            from: self)
    }

    /// What the pages of the tabs `ids` names show now, which copies of them
    /// start from.
    func sourcePages(for ids: Set<TabID>, in space: BrowserSpace) -> [SourcePage] {
        space.tabs.filter { ids.contains($0.id) }.map { source in
            let observed = tabCopying?.sourceForTabCopy(source, in: space) ?? source
            return SourcePage(tabID: source.id.rawValue, address: observed.url?.absoluteString, title: observed.title)
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

    /// Runs an intent the window issued in `space` that copies tabs, and
    /// prepares the pages of the copies it made. Answers the copies, or nil
    /// when the core refused it.
    @discardableResult
    func sendCopying(_ intent: some Intent, in space: BrowserSpace) -> [TabCopied]? {
        guard let sent = family.perform(intent, from: self) else { return nil }
        let copies: [TabCopied] = sent.changes.compactMap {
            guard case .tabCopied(let copied) = $0, copied.workspaceID == family.workspaceID else { return nil }
            return copied
        }
        prepareAcceptedCopies(copies, from: space)
        return copies
    }
}
