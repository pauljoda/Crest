import CrestCoreABI
import Foundation
import Observation

@Observable
@MainActor
final class BrowserSpaceAccessController {
    private(set) var authenticatingAssignment: BrowserSpaceRuntimeAssignment?
    private(set) var failure: BrowserSpaceAccessFailure?

    @ObservationIgnored private let authenticator: any BrowserDeviceAuthenticating
    @ObservationIgnored private let core = BrowserCoreSpaceAccess()
    /// The core session authority gates its commands on these same grants.
    var coreAccess: BrowserCoreSpaceAccess { core }
    @ObservationIgnored private var activeRequest: UInt64?
    private var accessRevision: UInt {
        get { observed(\.accessRevisionStorage, as: \.accessRevision) }
        set { publish(newValue, into: \.accessRevisionStorage, as: \.accessRevision) }
    }
    @ObservationIgnored private var accessRevisionStorage = UInt(0)
    init(
        authenticator: any BrowserDeviceAuthenticating = SystemBrowserDeviceAuthenticator()
    ) {
        self.authenticator = authenticator
    }

    func isLocked(_ space: BrowserSpace) -> Bool {
        _ = accessRevision
        return core.isLocked(space)
    }

    func isAuthenticating(_ space: BrowserSpace) -> Bool {
        authenticatingAssignment == BrowserSpaceRuntimeAssignment(space: space)
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

    @discardableResult
    func unlock(_ space: BrowserSpace) async -> Bool {
        let attempt = core.begin(space)
        guard attempt.status == CREST_OK else {
            if attempt.status != CREST_BUSY { failure = .authenticationUnavailable }
            return false
        }
        guard attempt.request != 0 else { return true }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let request = attempt.request
        activeRequest = request
        authenticatingAssignment = assignment
        failure = nil
        defer {
            if activeRequest == request {
                activeRequest = nil
                authenticatingAssignment = nil
            }
        }

        do {
            let authenticated = try await authenticator.authenticate(
                reason: String(
                    localized: "Authenticate to unlock the \(space.name) Space in Crest."
                )
            )
            guard core.complete(request, assignment: assignment, succeeded: authenticated) else { return false }
            guard authenticated else {
                failure = .authenticationDenied
                return false
            }
            // `accessRevision` is observed: both shells relock their page pools
            // from `lockedSpaceIDs`, so the withdrawal happens without a hook.
            accessRevision &+= 1
            return true
        } catch {
            guard core.complete(request, assignment: assignment, succeeded: false) else { return false }
            failure = .authenticationUnavailable
            return false
        }
    }

    func lock(_ spaceID: SpaceID) {
        core.lock(spaceID)
        accessRevision &+= 1
        if authenticatingAssignment?.spaceID == spaceID {
            activeRequest = nil
            authenticatingAssignment = nil
        }
    }

    func lockAllForInactiveScene() {
        guard core.lockAll(inactiveScene: true) else { return }
        publishLocked()
    }

    func lockAll() {
        _ = core.lockAll()
        publishLocked()
    }

    private func publishLocked() {
        accessRevision &+= 1
        activeRequest = nil
        authenticatingAssignment = nil
    }
}

extension BrowserSpaceAccessController: BrowserStoreFirstObservable {}
