import Foundation
import Observation

/// A Space of the read model. Its settings, each tab and each folder are
/// objects of their own, its sidebar lists are observed apart, and its
/// history and archive are kept apart, so a change notifies only the readers
/// of what it changed: a tab's new title redraws that tab's row, a move
/// redraws the one list it moves within, and a visit never redraws the
/// sidebar. Each of its
/// own values is stored before it is announced; see
/// `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class SpaceModel: ObservedModel, Identifiable {
    // MARK: - Variables

    let id: UUID
    let settings: SpaceSettingsModel
    let tabs: ObservedList<TabStateModel>
    let folders: ObservedList<FolderStateModel>
    /// What the sidebar lists, as the core publishes it.
    let sidebar: SidebarModel
    let history: HistoryModel
    let archive: ArchiveModel
    /// The profile the Space was made with, which never changes.
    let ownProfileID: UUID
    /// The profile the Space browses with: its own, or the session it shares
    /// as a Sub-Space.
    private(set) var profileID: UUID {
        get { observed(\.profileIDStorage, as: \.profileID) }
        set { publish(newValue, into: \.profileIDStorage, as: \.profileID) }
    }
    @ObservationIgnored private var profileIDStorage: UUID
    /// The session the Space shares besides its own, as the core resolved it.
    private(set) var membership: SpaceMembership? {
        get { observed(\.membershipStorage, as: \.membership) }
        set { publish(newValue, into: \.membershipStorage, as: \.membership) }
    }
    @ObservationIgnored private var membershipStorage: SpaceMembership?
    /// The Space whose pinned tabs this Space's sidebar shows in place of its
    /// own, as the core resolved it: its primary while its group shares pins.
    private(set) var pinOwnerID: UUID? {
        get { observed(\.pinOwnerIDStorage, as: \.pinOwnerID) }
        set { publish(newValue, into: \.pinOwnerIDStorage, as: \.pinOwnerID) }
    }
    @ObservationIgnored private var pinOwnerIDStorage: UUID?
    /// What a person chose for each split. Membership stays on the tabs.
    private(set) var splitGroups: [SplitGroupState] {
        get { observed(\.splitGroupsStorage, as: \.splitGroups) }
        set { publish(newValue, into: \.splitGroupsStorage, as: \.splitGroups) }
    }
    @ObservationIgnored private var splitGroupsStorage: [SplitGroupState]

    var value: SpaceState {
        SpaceState(
            id: id, ownProfileID: ownProfileID, settings: settings.value, folders: folders.values, tabs: tabs.values,
            splitGroups: splitGroups, archivedTabs: archive.entries, history: history.entries, membership: membership,
            profileID: profileID, pinOwnerID: pinOwnerID, sidebar: sidebar.outline(folders: folders.models))
    }

    /// The Spaces of the workspace that holds this one, which the workspace
    /// links so a Sub-Space can read the pinned tabs its group shares.
    @ObservationIgnored weak var siblings: ObservedList<SpaceModel>?

    /// The Space whose pinned tabs this Space's sidebar shows: its primary
    /// while its group shares them, otherwise itself.
    var pinSource: SpaceModel {
        pinOwnerID.flatMap { siblings?.model($0) } ?? self
    }

    /// Every tab the Space holds, open or archived.
    var tabIDs: [UUID] {
        tabs.models.map(\.id) + archive.entries.map(\.tab.id)
    }

    // MARK: - Initializers

    init(_ value: SpaceState) {
        id = value.id
        ownProfileID = value.ownProfileID
        profileIDStorage = value.profileID
        membershipStorage = value.membership
        pinOwnerIDStorage = value.pinOwnerID
        settings = SpaceSettingsModel(value.settings)
        tabs = ObservedList(value.tabs)
        folders = ObservedList(value.folders)
        sidebar = SidebarModel(value.sidebar)
        splitGroupsStorage = value.splitGroups
        history = HistoryModel(value.history)
        archive = ArchiveModel(value.archivedTabs)
    }

    /// Takes the Space again whole, keeping the object of every record it
    /// still holds.
    func update(_ value: SpaceState) {
        precondition(value.id == id, "A SpaceModel takes only its own Space's values.")
        profileID = value.profileID
        membership = value.membership
        pinOwnerID = value.pinOwnerID
        settings.update(value.settings)
        tabs.replace(with: value.tabs)
        folders.replace(with: value.folders)
        sidebar.replace(with: value.sidebar)
        splitGroups = value.splitGroups
        history.replace(with: value.history)
        archive.replace(with: value.archivedTabs)
    }

    // MARK: - Actions - Reading

    /// Whether the Space holds the tab, open or archived.
    func holds(tabID: UUID) -> Bool {
        tabs.contains(tabID) || archive.contains(tabID: tabID)
    }

    /// A tab the Space's sidebar shows: one the Space holds, or a pinned tab
    /// its group shares, which its primary holds.
    func shownTab(_ tabID: UUID) -> TabStateModel? {
        if let tab = tabs.model(tabID) { return tab }
        let source = pinSource
        guard source !== self, let tab = source.tabs.model(tabID), tab.placement == .pinned else { return nil }
        return tab
    }

    /// The Spaces of this Space's group as its workspace lists them, the
    /// primary first: a primary and the Sub-Spaces that joined its session,
    /// or this Space alone.
    var groupMembers: [SpaceModel] {
        let primaryID = membership?.primaryID ?? id
        let members = siblings?.models.filter { $0.id == primaryID || $0.membership?.primaryID == primaryID } ?? []
        return members.isEmpty ? [self] : members
    }

    /// The history of this Space's group, newest visit first: what its
    /// primary keeps for the group and what each member kept before it
    /// joined.
    var groupHistory: [HistoryEntryState] {
        let members = groupMembers
        guard members.count > 1 else { return history.entries }
        return members.flatMap(\.history.entries).sorted { $0.lastVisitedAt > $1.lastVisitedAt }
    }

    /// The pinned tabs the Space's sidebar shows, in order: the ones its
    /// group shares, or its own.
    var shownPins: [TabStateModel] {
        let source = pinSource
        return source.sidebar.section(.pinned).rows.compactMap { source.tabs.model($0.id) }
    }

    // MARK: - Actions - Changes

    func apply(_ change: SpaceSettingsChanged) {
        settings.update(change.settings)
    }

    func apply(_ change: TabsChanged) {
        tabs.apply(updated: change.updated, removed: change.removed, order: change.order)
    }

    func apply(_ change: FoldersChanged) {
        folders.apply(updated: change.updated, removed: change.removed, order: change.order)
    }

    func apply(_ change: SplitGroupsChanged) {
        splitGroups = change.groups
    }

    func apply(_ change: SidebarChanged) {
        sidebar.apply(change)
    }

    func apply(_ change: HistoryChanged) {
        history.apply(change)
    }

    func apply(_ change: ArchiveChanged) {
        archive.apply(change)
    }
}

extension SpaceModel: BrowserStoreFirstObservable {}
