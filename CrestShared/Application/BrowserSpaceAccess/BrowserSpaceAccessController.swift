import Foundation
import Observation

@Observable
@MainActor
final class BrowserSpaceAccessController {
    private(set) var authenticatingAssignment: BrowserSpaceRuntimeAssignment?
    private(set) var failure: BrowserSpaceAccessFailure?

    @ObservationIgnored private let authenticator: any BrowserDeviceAuthenticating
    @ObservationIgnored private var lockGeneration: UInt = 0
    private var unlockedAssignments: Set<BrowserSpaceRuntimeAssignment> = []

    init(
        authenticator: any BrowserDeviceAuthenticating = SystemBrowserDeviceAuthenticator()
    ) {
        self.authenticator = authenticator
    }

    func isLocked(_ space: BrowserSpace) -> Bool {
        space.accessPolicy.requiresAuthentication
            && !unlockedAssignments.contains(
                BrowserSpaceRuntimeAssignment(space: space)
            )
    }

    func isAuthenticating(_ space: BrowserSpace) -> Bool {
        authenticatingAssignment == BrowserSpaceRuntimeAssignment(space: space)
    }

    @discardableResult
    func unlock(_ space: BrowserSpace) async -> Bool {
        guard isLocked(space) else { return true }
        guard authenticatingAssignment == nil else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let generation = lockGeneration
        authenticatingAssignment = assignment
        failure = nil
        defer {
            if generation == lockGeneration {
                authenticatingAssignment = nil
            }
        }

        do {
            let authenticated = try await authenticator.authenticate(
                reason: String(
                    localized: "Authenticate to unlock the \(space.name) Space in Crest."
                )
            )
            guard generation == lockGeneration else { return false }
            guard authenticated else {
                failure = .authenticationDenied
                return false
            }
            unlockedAssignments.insert(assignment)
            return true
        } catch {
            guard generation == lockGeneration else { return false }
            failure = .authenticationUnavailable
            return false
        }
    }

    func lock(_ spaceID: SpaceID) {
        unlockedAssignments = Set(
            unlockedAssignments.filter { $0.spaceID != spaceID }
        )
        if authenticatingAssignment?.spaceID == spaceID {
            lockGeneration &+= 1
            authenticatingAssignment = nil
        }
    }

    func lockAllForInactiveScene() {
        guard authenticatingAssignment == nil else { return }
        lockAll()
    }

    func lockAll() {
        lockGeneration &+= 1
        unlockedAssignments.removeAll()
        authenticatingAssignment = nil
    }
}
