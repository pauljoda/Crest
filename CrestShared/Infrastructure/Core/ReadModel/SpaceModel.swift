import Foundation
import Observation

/// A Space of the read model. Its settings, each tab and each folder are
/// objects of their own, and its history and archive are kept apart, so a
/// change notifies only the readers of what it changed: a tab's new title
/// redraws that tab's row, and a visit never redraws the sidebar.
@MainActor
@Observable
final class SpaceModel: ObservedModel, Identifiable {
    // MARK: - Variables

    let id: UUID
    let settings: SpaceSettingsModel
    let tabs: ObservedList<TabStateModel>
    let folders: ObservedList<FolderStateModel>
    let history: HistoryModel
    let archive: ArchiveModel
    private(set) var profileID: UUID
    /// What a person chose for each split. Membership stays on the tabs.
    private(set) var splitGroups: [SplitGroupState]

    var value: SpaceState {
        SpaceState(
            id: id, profileID: profileID, settings: settings.value, folders: folders.values, tabs: tabs.values,
            splitGroups: splitGroups, archivedTabs: archive.entries, history: history.entries)
    }

    /// Every tab the Space holds, open or archived.
    var tabIDs: [UUID] {
        tabs.models.map(\.id) + archive.entries.map(\.tab.id)
    }

    // MARK: - Initializers

    init(_ value: SpaceState) {
        id = value.id
        profileID = value.profileID
        settings = SpaceSettingsModel(value.settings)
        tabs = ObservedList(value.tabs)
        folders = ObservedList(value.folders)
        splitGroups = value.splitGroups
        history = HistoryModel(value.history)
        archive = ArchiveModel(value.archivedTabs)
    }

    /// Takes the Space again whole, keeping the object of every record it
    /// still holds.
    func update(_ value: SpaceState) {
        precondition(value.id == id, "A SpaceModel takes only its own Space's values.")
        if profileID != value.profileID { profileID = value.profileID }
        settings.update(value.settings)
        tabs.replace(with: value.tabs)
        folders.replace(with: value.folders)
        replaceSplitGroups(with: value.splitGroups)
        history.replace(with: value.history)
        archive.replace(with: value.archivedTabs)
    }

    // MARK: - Actions - Reading

    /// Whether the Space holds the tab, open or archived.
    func holds(tabID: UUID) -> Bool {
        tabs.contains(tabID) || archive.contains(tabID: tabID)
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
        replaceSplitGroups(with: change.groups)
    }

    func apply(_ change: HistoryChanged) {
        history.apply(change)
    }

    func apply(_ change: ArchiveChanged) {
        archive.apply(change)
    }

    private func replaceSplitGroups(with groups: [SplitGroupState]) {
        if splitGroups != groups { splitGroups = groups }
    }
}
