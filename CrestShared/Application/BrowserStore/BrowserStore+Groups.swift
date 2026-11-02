import Foundation

/// The groups of this window's workspace, read from the core's read model. A
/// group is a primary and the Sub-Spaces that joined its session, in order:
/// they browse with one profile, the primary keeps the group's history and
/// passwords, and its pinned tabs show in every Sub-Space unless the group
/// keeps them apart. A Space on its own is a group of one.
extension BrowserStore {
    // MARK: - Actions - Reading

    /// The primary of the group `space` belongs to: the Space whose session it
    /// joined, or the Space itself.
    func primary(of space: SpaceModel) -> SpaceModel {
        space.membership?.primaryID.flatMap(spaceModel) ?? space
    }

    /// The Spaces of the group `space` belongs to that stay, the primary
    /// first and then its Sub-Spaces in order.
    func groupMembers(of space: SpaceModel) -> [SpaceModel] {
        let primaryID = primary(of: space).id
        return spaceModels.filter {
            ($0.id == primaryID || $0.membership?.primaryID == primaryID) && !isDeleting($0.id)
        }
    }

    /// Whether `space` leads Sub-Spaces that stay.
    func leadsGroup(_ space: SpaceModel) -> Bool {
        groupMembers(of: space).count > 1 && primary(of: space) === space
    }

    /// Whether `space` is a Sub-Space: it joined another Space's session.
    func isSubSpace(_ space: SpaceModel) -> Bool {
        space.membership?.primaryID != nil
    }

    /// Whether `space` may become a Sub-Space of another group: a Space on its
    /// own, or a Sub-Space, but never a primary, which owns its session.
    func canJoinGroup(_ space: SpaceModel) -> Bool {
        !isPrivateBrowsing && !leadsGroup(space)
            && (isSubSpace(space) || space.membership?.sharedProfileID == nil)
    }

    /// The groups `space` may join, by the Space each is shown as, its
    /// primary: every other group of the workspace.
    func joinableGroups(for space: SpaceModel) -> [SpaceModel] {
        let own = primary(of: space).id
        return spaceModels.filter { !isDeleting($0.id) && !isSubSpace($0) && $0.id != own && $0.id != space.id }
    }

    /// The Spaces of this window's workspace grouped as the picker and the
    /// Settings list show them, each group its primary then its Sub-Spaces.
    var spaceGroups: [[SpaceModel]] {
        var groups: [[SpaceModel]] = []
        for space in spaceModels where !isDeleting(space.id) {
            if isSubSpace(space), let last = groups.indices.last,
                groups[last].first?.id == space.membership?.primaryID
            {
                groups[last].append(space)
            } else {
                groups.append([space])
            }
        }
        return groups
    }

    /// `spaces`, in their order, split where one group ends and the next
    /// begins, as menus that list Spaces separate them.
    func grouped(_ spaces: [SpaceModel]) -> [[SpaceModel]] {
        var groups: [[SpaceModel]] = []
        for space in spaces {
            if let last = groups.last?.last, primary(of: last) === primary(of: space) {
                groups[groups.count - 1].append(space)
            } else {
                groups.append([space])
            }
        }
        return groups
    }

    /// The Spaces whose passwords the group of `spaceID` reads, the one that
    /// keeps its new passwords first: the group's primary, then the Sub-Spaces,
    /// which keep what they saved before they joined.
    func credentialSpaceIDs(of spaceID: UUID) -> [UUID] {
        guard let space = spaceModel(spaceID) else { return [spaceID] }
        return groupMembers(of: space).map(\.id)
    }

    // MARK: - Actions - Changing groups

    /// Adds a Sub-Space right after `spaceID`, which joins that Space's group,
    /// and shows it in this window. Answers whether the core added it.
    @discardableResult
    func addSubSpace(after spaceID: UUID) -> Bool {
        family.send(
            AddSubSpace(workspaceID: family.workspaceID, windowID: windowID, spaceID: UUID(), fromSpaceID: spaceID),
            from: self, failure: "Core Space command failed")
    }

    /// Makes `spaceID` a Sub-Space of the group `groupSpaceID` belongs to.
    /// Throws the rule the core refused it with.
    func join(_ spaceID: UUID, toGroupOf groupSpaceID: UUID) throws(Rejection) {
        try family.commit(
            JoinSpace(workspaceID: family.workspaceID, spaceID: spaceID, groupSpaceID: groupSpaceID), from: self)
    }

    /// Separates the Sub-Space `spaceID` from its group. Throws the rule the
    /// core refused it with.
    func separate(_ spaceID: UUID) throws(Rejection) {
        try family.commit(SeparateSpace(workspaceID: family.workspaceID, spaceID: spaceID), from: self)
    }

    /// Sets whether the Sub-Spaces of `spaceID`'s group each show their own
    /// pinned tabs.
    func setSeparatePinnedTabs(_ separates: Bool, in spaceID: UUID) {
        sendSpaceSettings(
            SetSeparatePinnedTabs(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID, separates: separates))
    }

    /// Moves `spaceID` to where `targetID` stands: before it when it comes
    /// from further on, after it when it comes from earlier. The core keeps
    /// every group together, its primary first.
    func move(_ spaceID: UUID, to targetID: UUID) {
        var order = spaceModels.map(\.id)
        guard let from = order.firstIndex(of: spaceID), let to = order.firstIndex(of: targetID), from != to else {
            return
        }
        order.remove(at: from)
        order.insert(spaceID, at: to)
        orderSpaces(order)
    }

    /// Moves `spaceID` to stand right before `targetID`.
    func move(_ spaceID: UUID, before targetID: UUID) {
        var order = spaceModels.map(\.id)
        guard spaceID != targetID, let from = order.firstIndex(of: spaceID) else { return }
        order.remove(at: from)
        guard let to = order.firstIndex(of: targetID) else { return }
        order.insert(spaceID, at: to)
        orderSpaces(order)
    }

    /// Moves the group `spaceID` belongs to, whole, to stand right before the
    /// group `targetID` leads, or last when there is none.
    func moveGroup(of spaceID: UUID, before targetID: UUID?) {
        var groups = spaceGroups
        guard let from = groups.firstIndex(where: { $0.contains { $0.id == spaceID } }),
            !groups[from].contains(where: { $0.id == targetID })
        else { return }
        let group = groups.remove(at: from)
        let to = targetID.flatMap { id in groups.firstIndex { $0[0].id == id } } ?? groups.count
        groups.insert(group, at: to)
        // The core orders every Space, those being deleted too.
        orderSpaces(groups.flatMap { $0.map(\.id) } + spaceModels.map(\.id).filter(isDeleting))
    }

    /// Puts the workspace's Spaces in the order `spaceIDs` lists; the core
    /// keeps every group together.
    func orderSpaces(_ spaceIDs: [UUID]) {
        family.send(
            ReorderSpaces(workspaceID: family.workspaceID, spaceIDs: spaceIDs), from: self,
            failure: "Core Space command failed")
    }

}
