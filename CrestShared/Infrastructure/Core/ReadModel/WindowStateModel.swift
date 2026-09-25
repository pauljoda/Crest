import Foundation
import Observation

/// What one open window shows, as the read model keeps it: each field of the
/// core's `WindowState` observed on its own, and the tabs it shows as a set
/// observed tab by tab, so a sidebar row reads only whether its own tab is
/// shown and showing another tab redraws two rows and no list. Written by
/// hand for those slots; `CoreReadModelTests` fails when `WindowState` gains
/// a field this model does not carry. Each value is stored before it is
/// announced; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class WindowStateModel: ObservedModel, Identifiable {
    // MARK: - Variables

    let id: UUID
    private(set) var workspaceID: UUID {
        get { observed(\.workspaceIDStorage, as: \.workspaceID) }
        set { publish(newValue, into: \.workspaceIDStorage, as: \.workspaceID) }
    }
    @ObservationIgnored private var workspaceIDStorage: UUID
    private(set) var shownSpaceID: UUID {
        get { observed(\.shownSpaceIDStorage, as: \.shownSpaceID) }
        set { publish(newValue, into: \.shownSpaceIDStorage, as: \.shownSpaceID) }
    }
    @ObservationIgnored private var shownSpaceIDStorage: UUID
    /// The tab the window shows in each Space it has shown. Reading it
    /// observes every Space's; a row reads `shownTabIDs` instead.
    private(set) var shownTabs: [ShownTab] {
        get { observed(\.shownTabsStorage, as: \.shownTabs) }
        set { publish(newValue, into: \.shownTabsStorage, as: \.shownTabs) }
    }
    @ObservationIgnored private var shownTabsStorage: [ShownTab]
    private(set) var splitColumnShares: [SplitColumnShares] {
        get { observed(\.splitColumnSharesStorage, as: \.splitColumnShares) }
        set { publish(newValue, into: \.splitColumnSharesStorage, as: \.splitColumnShares) }
    }
    @ObservationIgnored private var splitColumnSharesStorage: [SplitColumnShares]
    /// The tabs the window shows, one per Space it has shown, each observed
    /// on its own. A tab lives in one Space, so a row of any Space's sidebar
    /// is shown exactly when its tab is here.
    let shownTabIDs: ObservedSet<UUID>

    var value: WindowState {
        WindowState(
            id: id, workspaceID: workspaceID, shownSpaceID: shownSpaceID, shownTabs: shownTabs,
            splitColumnShares: splitColumnShares)
    }

    // MARK: - Initializers

    init(_ value: WindowState) {
        id = value.id
        workspaceIDStorage = value.workspaceID
        shownSpaceIDStorage = value.shownSpaceID
        shownTabsStorage = value.shownTabs
        splitColumnSharesStorage = value.splitColumnShares
        shownTabIDs = ObservedSet(Set(value.shownTabs.compactMap(\.tabID)))
    }

    // MARK: - Actions - Changes

    /// Takes the window's next value, announcing only the fields that differ
    /// and the tabs that are shown or no longer shown.
    func update(_ value: WindowState) {
        precondition(value.id == id, "A WindowStateModel takes only its own WindowState's values.")
        workspaceID = value.workspaceID
        shownSpaceID = value.shownSpaceID
        shownTabs = value.shownTabs
        splitColumnShares = value.splitColumnShares
        shownTabIDs.replace(with: Set(value.shownTabs.compactMap(\.tabID)))
    }
}

extension WindowStateModel: BrowserStoreFirstObservable {}
