import Observation
import SwiftUI

/// Workspace-owned, memory-only state for loaded native tabs. Views may disappear
/// without ending this lifetime; unloading or changing the assignment ends it.
@Observable @MainActor
final class BrowserNativeTabStore {
    @ObservationIgnored private var runtimes: [TabID: BrowserNativeTabRuntime] = [:]
    private(set) var residencyRevision = 0

    var tabIDs: Set<TabID> {
        _ = residencyRevision
        return Set(runtimes.keys)
    }

    func runtime(
        matching assignment: BrowserTabRuntimeAssignment,
        content: BrowserNativeTabContent
    ) -> BrowserNativeTabRuntime? {
        _ = residencyRevision
        guard let runtime = runtimes[assignment.tabID],
            runtime.assignment == assignment, runtime.content == content
        else { return nil }
        return runtime
    }

    func contains(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        _ = residencyRevision
        return runtimes[assignment.tabID]?.assignment == assignment
    }

    func load(tab: BrowserTab, space: BrowserSpace, at time: Date = .now) {
        guard let content = tab.nativeContent else { return }
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        if let runtime = runtime(matching: assignment, content: content) {
            runtime.lastPresented = time
        } else {
            runtimes[tab.id] = BrowserNativeTabRuntime(assignment: assignment, content: content, at: time)
            residencyRevision &+= 1
        }
    }

    /// Moves the loaded model without rebuilding native content or copying its
    /// state. Matching assignments remain mandatory across workspace owners.
    @discardableResult
    func transfer(matching assignment: BrowserTabRuntimeAssignment, to destination: BrowserNativeTabStore) -> Bool {
        guard destination !== self else { return true }
        guard let runtime = runtimes[assignment.tabID], runtime.assignment == assignment,
            destination.runtimes[assignment.tabID] == nil
        else { return false }
        runtimes.removeValue(forKey: assignment.tabID)
        destination.runtimes[assignment.tabID] = runtime
        residencyRevision &+= 1
        destination.residencyRevision &+= 1
        return true
    }

    func remove(_ tabID: TabID) {
        if runtimes.removeValue(forKey: tabID) != nil { residencyRevision &+= 1 }
    }

    @discardableResult
    func remove(tabID: TabID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard
            contains(
                BrowserTabRuntimeAssignment(
                    tabID: tabID, spaceID: assignment.spaceID, profileID: assignment.profileID))
        else { return false }
        remove(tabID)
        return true
    }

    func remove(in spaceID: SpaceID) {
        for id in tabIDs(in: spaceID) { remove(id) }
    }

    func tabIDs(in spaceID: SpaceID) -> Set<TabID> {
        _ = residencyRevision
        return Set(runtimes.keys.filter { runtimes[$0]?.assignment.spaceID == spaceID })
    }

    func reconcile(validTabIDs: Set<TabID>) {
        for id in runtimes.keys.filter({ !validTabIDs.contains($0) }) { remove(id) }
    }

    func reconcile(session: BrowserSession) {
        let live = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.tabs.map { tab in
                    (
                        tab.id,
                        (
                            BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id),
                            tab.nativeContent
                        )
                    )
                }
            })
        let removed = runtimes.compactMap { id, runtime in
            live[id]?.0 == runtime.assignment && live[id]?.1 == runtime.content ? nil : id
        }
        for id in removed { remove(id) }
    }

    func inactiveTabIDs(excluding presented: [TabID]) -> [TabID] {
        runtimes.values.filter { !presented.contains($0.assignment.tabID) }
            .sorted {
                if $0.lastPresented != $1.lastPresented { return $0.lastPresented < $1.lastPresented }
                return $0.assignment.tabID.uuidString < $1.assignment.tabID.uuidString
            }
            .map(\.assignment.tabID)
    }
}

@MainActor
final class BrowserNativeTabRuntime: Identifiable {
    let id = UUID()
    let assignment: BrowserTabRuntimeAssignment
    let content: BrowserNativeTabContent
    var lastPresented: Date
    private var models: [ObjectIdentifier: AnyObject] = [:]

    init(assignment: BrowserTabRuntimeAssignment, content: BrowserNativeTabContent, at time: Date = .now) {
        self.assignment = assignment
        self.content = content
        lastPresented = time
    }

    /// Content owns its typed model. The host owns only the loaded lifetime.
    /// Lazy creation does not publish an observation change during rendering.
    func model<Model: AnyObject>(_ type: Model.Type, make: () -> Model) -> Model {
        let key = ObjectIdentifier(type)
        if let model = models[key] as? Model { return model }
        let model = make()
        models[key] = model
        return model
    }
}

private struct BrowserNativeTabStoreKey: EnvironmentKey {
    static let defaultValue: BrowserNativeTabStore? = nil
}

extension EnvironmentValues {
    var browserNativeTabs: BrowserNativeTabStore? {
        get { self[BrowserNativeTabStoreKey.self] }
        set { self[BrowserNativeTabStoreKey.self] = newValue }
    }
}
