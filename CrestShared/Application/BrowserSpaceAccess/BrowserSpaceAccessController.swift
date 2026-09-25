import Foundation
import Observation

/// The app's one Space access controller. The core keeps the grants and the
/// request waiting on the device owner; this controller presents the system's
/// authentication prompt and answers the core with its result, and views read
/// each Space's lock from the core's published access.
@Observable
@MainActor
final class BrowserSpaceAccessController {
    // MARK: - Types

    private struct WeakStore {
        weak var value: BrowserStore?
    }

    // MARK: - Variables

    private(set) var failure: BrowserSpaceAccessFailure?

    @ObservationIgnored private let authenticator: any BrowserDeviceAuthenticating
    /// The core whose grants these are, once a store is attached.
    @ObservationIgnored private var core: CrestCore?
    /// The stores whose workspaces show the Spaces this controller unlocks.
    @ObservationIgnored private var stores: [WeakStore] = []

    /// The Space profile whose unlock is waiting on the device owner.
    var authenticatingAssignment: BrowserSpaceRuntimeAssignment? {
        core?.state.spaceAccess.first { $0.value.isAuthenticating }?.key
    }

    // MARK: - Initializers

    init(
        authenticator: any BrowserDeviceAuthenticating = SystemBrowserDeviceAuthenticator()
    ) {
        self.authenticator = authenticator
    }

    // MARK: - Actions - Stores

    /// Unlocks Spaces the workspace of `store` shows, through its core.
    func attach(_ store: BrowserStore) {
        core = store.core
        stores.removeAll { $0.value == nil || $0.value === store }
        stores.append(WeakStore(value: store))
    }

    // MARK: - Actions - Access

    /// A Space that asks for authentication shows only while this process
    /// holds the grant for its profile.
    func isLocked(_ space: BrowserSpace) -> Bool {
        guard space.accessPolicy.requiresAuthentication else { return false }
        return core?.state.spaceAccess[BrowserSpaceRuntimeAssignment(space: space)]?.isUnlocked != true
    }

    func isAuthenticating(_ space: BrowserSpace) -> Bool {
        core?.state.spaceAccess[BrowserSpaceRuntimeAssignment(space: space)]?.isAuthenticating == true
    }

    /// Authentication authorizes one profile identity. A window may replace or
    /// delete that profile while the system prompt is awaiting a response.
    @discardableResult
    func updatePolicy(
        _ policy: BrowserSpaceAccessPolicy,
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore
    ) async -> Bool {
        guard let space = browser.space(matching: assignment) else { return false }
        if !policy.requiresAuthentication {
            guard await unlock(space) else { return false }
        }
        guard browser.space(matching: assignment) != nil else { return false }
        browser.updateSpaceAccessPolicy(policy, in: assignment.spaceID)
        if policy.requiresAuthentication {
            lock(assignment.spaceID)
        }
        return true
    }

    /// Asks the device owner to unlock `space`, answering whether it is
    /// unlocked afterwards. One request waits at a time; only its own answer
    /// can unlock the Space, so a lock while the prompt is up keeps it locked.
    @discardableResult
    func unlock(_ space: BrowserSpace) async -> Bool {
        guard isLocked(space) else { return true }
        guard let core, let workspace = workspace(showing: BrowserSpaceRuntimeAssignment(space: space)) else {
            failure = .authenticationUnavailable
            return false
        }
        let request = UUID()
        do throws(Rejection) {
            try core.send(BeginUnlockingSpace(workspaceID: workspace, spaceID: space.id, requestID: request))
        } catch {
            if case .authenticationBusy = error { return false }
            failure = .authenticationUnavailable
            return false
        }
        guard isAuthenticating(space) else { return !isLocked(space) }
        failure = nil
        do {
            let authenticated = try await authenticator.authenticate(
                reason: String(
                    localized: "Authenticate to unlock the \(space.name) Space in Crest."
                )
            )
            guard finish(request, for: space, authenticated: authenticated) else { return false }
            guard authenticated else {
                failure = .authenticationDenied
                return false
            }
            return true
        } catch {
            guard finish(request, for: space, authenticated: false) else { return false }
            failure = .authenticationUnavailable
            return false
        }
    }

    func lock(_ spaceID: SpaceID) {
        _ = try? core?.send(LockSpace(spaceID: spaceID))
    }

    /// The scene went inactive, which the system's own authentication prompt
    /// also causes: while an unlock waits on it, nothing locks.
    func lockAllForInactiveScene() {
        _ = try? core?.send(LockAllSpaces(sceneWentInactive: true))
    }

    func lockAll() {
        _ = try? core?.send(LockAllSpaces(sceneWentInactive: false))
    }

    /// Answers the core's waiting request, and whether it was still the one
    /// waiting.
    private func finish(_ request: UUID, for space: BrowserSpace, authenticated: Bool) -> Bool {
        (try? core?.send(
            FinishUnlockingSpace(spaceID: space.id, requestID: request, authenticated: authenticated))) != nil
    }

    /// The workspace of an attached store that shows the Space profile.
    private func workspace(showing assignment: BrowserSpaceRuntimeAssignment) -> UUID? {
        stores.compactMap(\.value).first { $0.space(matching: assignment) != nil }?.family.workspaceID
    }
}
