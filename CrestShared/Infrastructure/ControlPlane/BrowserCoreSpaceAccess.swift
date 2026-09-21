import CrestCoreABI
import Foundation

/// Thin native port. The core owns grants and pending authentication identities;
/// native views only observe their changes and the platform presents the prompt.
@MainActor
final class BrowserCoreSpaceAccess {
    private let handle: UInt64

    init() {
        var value: UInt64 = 0
        precondition(crest_access_create(&value) == CREST_OK, "Could not initialize Space access")
        handle = value
    }

    deinit { crest_access_destroy(handle) }

    func isLocked(_ space: BrowserSpace) -> Bool {
        var locked: Int32 = 1
        let result = withIdentity(BrowserSpaceRuntimeAssignment(space: space)) {
            crest_access_is_locked(handle, $0, $1, space.accessPolicy.requiresAuthentication ? 1 : 0, &locked)
        }
        return result != CREST_OK || locked != 0
    }

    func begin(_ space: BrowserSpace) -> (status: Int32, request: UInt64) {
        var request: UInt64 = 0
        let result = withIdentity(BrowserSpaceRuntimeAssignment(space: space)) {
            crest_access_begin(handle, $0, $1, space.accessPolicy.requiresAuthentication ? 1 : 0, &request)
        }
        return (result, request)
    }

    func complete(_ request: UInt64, assignment: BrowserSpaceRuntimeAssignment, succeeded: Bool) -> Bool {
        withIdentity(assignment) {
            crest_access_complete(handle, $0, $1, request, succeeded ? 1 : 0)
        } == CREST_OK
    }

    func lock(_ space: SpaceID) {
        var uuid = space.rawValue.uuid
        let result = withUnsafeBytes(of: &uuid) {
            crest_access_lock_space(handle, $0.bindMemory(to: UInt8.self).baseAddress)
        }
        precondition(result == CREST_OK, "Could not lock Space")
    }

    func lockAll(inactiveScene: Bool = false) -> Bool {
        var applied: Int32 = 0
        precondition(crest_access_lock_all(handle, inactiveScene ? 1 : 0, &applied) == CREST_OK,
            "Could not lock Spaces")
        return applied != 0
    }

    private func withIdentity<T>(_ assignment: BrowserSpaceRuntimeAssignment,
        _ operation: (UnsafePointer<UInt8>?, UnsafePointer<UInt8>?) -> T) -> T {
        var space = assignment.spaceID.rawValue.uuid
        var profile = assignment.profileID.uuid
        return withUnsafeBytes(of: &space) { space in
            withUnsafeBytes(of: &profile) { profile in
                operation(space.bindMemory(to: UInt8.self).baseAddress,
                    profile.bindMemory(to: UInt8.self).baseAddress)
            }
        }
    }
}
