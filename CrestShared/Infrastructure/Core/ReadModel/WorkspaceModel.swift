import Foundation
import Observation

/// A workspace attached to this device, as the read model keeps it: what kind
/// of session it is, its own members and its Spaces in order. Each Space is an
/// object of its own, so a change inside one Space never notifies the readers
/// of the Space list.
@MainActor
@Observable
final class WorkspaceModel: Identifiable {
    // MARK: - Variables

    let id: UUID
    let kind: WorkspaceKind
    let spaces: ObservedList<SpaceModel>
    /// Space deletions under way on this device.
    private(set) var spaceDeletions: [SpaceDeletionState]
    /// The app-wide preferences, or nil before the settings kept before the
    /// core owned them are imported. Preferences change together and seldom,
    /// so they are one observed value.
    private(set) var appPreferences: AppPreferences?
    /// The Space a launch opens.
    private(set) var defaultSpaceID: UUID?
    /// The session is still the disposable first-install seed.
    private(set) var isDisposableSeed: Bool

    /// Every tab the workspace holds, open or archived.
    var tabIDs: [UUID] {
        spaces.models.flatMap(\.tabIDs)
    }

    // MARK: - Initializers

    init(_ change: WorkspaceOpened) {
        id = change.workspaceID
        kind = change.kind
        spaces = ObservedList(change.session.spaces)
        spaceDeletions = change.session.spaceDeletions
        appPreferences = change.session.appPreferences
        defaultSpaceID = change.session.defaultSpaceID
        isDisposableSeed = change.session.disposableSeedMarker != nil
    }

    // MARK: - Actions - Reading

    /// Whether any Space of the workspace holds the tab, open or archived.
    func holds(tabID: UUID) -> Bool {
        spaces.models.contains { $0.holds(tabID: tabID) }
    }

    /// Whether any Space of the workspace holds the tab open.
    func holdsOpen(tabID: UUID) -> Bool {
        spaces.models.contains { $0.tabs.contains(tabID) }
    }

    // MARK: - Actions - Changes

    /// The workspace joined again: it takes the whole session, keeping the
    /// object of every record the session still holds.
    func apply(_ change: WorkspaceOpened) {
        precondition(change.workspaceID == id, "A WorkspaceModel takes only its own workspace's session.")
        spaces.replace(with: change.session.spaces)
        apply(
            WorkspaceChanged(
                workspaceID: id, defaultSpaceID: change.session.defaultSpaceID,
                isDisposableSeed: change.session.disposableSeedMarker != nil,
                spaceDeletions: change.session.spaceDeletions))
        apply(AppPreferencesChanged(workspaceID: id, preferences: change.session.appPreferences))
    }

    func apply(_ change: WorkspaceChanged) {
        if defaultSpaceID != change.defaultSpaceID { defaultSpaceID = change.defaultSpaceID }
        if isDisposableSeed != change.isDisposableSeed { isDisposableSeed = change.isDisposableSeed }
        if spaceDeletions != change.spaceDeletions { spaceDeletions = change.spaceDeletions }
    }

    func apply(_ change: AppPreferencesChanged) {
        if appPreferences != change.preferences { appPreferences = change.preferences }
    }

    /// The `removed` Spaces are gone and each `added` Space arrives whole
    /// after the Spaces that stay. A Space named in both arrives again whole
    /// and keeps its object, which takes the Space's new records.
    func apply(_ change: SpacesChanged) {
        let gone = Set(change.removed)
        let staying = spaces.models.map(\.id).filter { !gone.contains($0) }
        let stayingIDs = Set(staying)
        let arriving = Set(change.added.map(\.id))
        let order = change.order ?? staying + change.added.map(\.id).filter { !stayingIDs.contains($0) }
        spaces.apply(updated: change.added, removed: change.removed.filter { !arriving.contains($0) }, order: order)
    }
}
