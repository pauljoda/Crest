import AppKit
import Observation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceAccessTests: XCTestCase {

    func testChosenDefaultSpaceBecomesTheLaunchSelection() throws {
        let store = BrowserStore(session: .preview)
        let work = try XCTUnwrap(store.session.spaces.first)
        let personal = try XCTUnwrap(store.session.spaces.last)

        store.setDefaultSpace(personal.id)
        store.selectSpace(work.id)

        XCTAssertEqual(store.session.defaultSpaceID, personal.id)
        XCTAssertEqual(store.selectedSpaceID, work.id)
        XCTAssertEqual(BrowserStoreSelection(launching: store.session).selectedSpaceID, personal.id)
    }

    func testLegacySessionAndSpaceDecodeWithSafeAccessDefaults() throws {
        let encoded = try JSONEncoder().encode(BrowserSession.preview)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "defaultSpaceID")
        var spaces = try XCTUnwrap(object["spaces"] as? [[String: Any]])
        for index in spaces.indices {
            spaces[index].removeValue(forKey: "accessPolicy")
        }
        object["spaces"] = spaces
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        var decoded = try JSONDecoder().decode(BrowserSession.self, from: legacyData)
        decoded = try BrowserCoreSync.repair(decoded)

        XCTAssertEqual(decoded.defaultSpaceID, decoded.spaces.first?.id)
        XCTAssertTrue(decoded.spaces.allSatisfy { $0.accessPolicy == .open })
    }

    func testPrivateSpaceRemainsLockedUntilDeviceOwnerAuthenticationSucceeds() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let authenticator = BrowserDeviceAuthenticatorStub(results: [.success(true)])
        let access = BrowserSpaceAccessController(authenticator: authenticator)

        XCTAssertTrue(access.isLocked(space))
        let unlocked = await access.unlock(space)

        XCTAssertTrue(unlocked)
        XCTAssertFalse(access.isLocked(space))
        XCTAssertEqual(
            authenticator.reasons,
            [
                "Authenticate to unlock the Work Space in Crest."
            ])
    }

    func testSuccessfulAuthenticationPublishesTheUnlockedState() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(
            authenticator: BrowserDeviceAuthenticatorStub(results: [.success(true)])
        )
        let stateChanged = expectation(description: "Unlocked state published")
        withObservationTracking {
            _ = access.isLocked(space)
        } onChange: {
            stateChanged.fulfill()
        }

        let unlocked = await access.unlock(space)

        await fulfillment(of: [stateChanged], timeout: 1)
        XCTAssertTrue(unlocked)
        XCTAssertFalse(access.isLocked(space))
    }

    func testUnlockFollowsExactSpaceAndProfileIdentityAcrossSessionChanges() async throws {
        var original = try XCTUnwrap(BrowserSession.preview.spaces.first)
        original.accessPolicy = .deviceOwnerAuthentication
        let authenticator = BrowserDeviceAuthenticatorStub(
            results: [.success(true), .success(true)]
        )
        let access = BrowserSpaceAccessController(authenticator: authenticator)

        let didUnlockOriginal = await access.unlock(original)
        XCTAssertTrue(didUnlockOriginal)

        var renamed = original
        renamed.name = "Renamed"
        XCTAssertFalse(access.isLocked(renamed))

        let replacement = BrowserSpace(
            id: original.id,
            profile: BrowsingProfile(
                id: UUID(
                    uuid: (
                        0x41, 0x43, 0x43, 0x45, 0x53, 0x53, 0x54, 0x45,
                        0x53, 0x54, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                    )
                )
            ),
            name: original.name,
            symbol: original.symbol,
            accent: original.accent,
            branding: original.branding,
            folders: original.folders,
            tabs: original.tabs,
            archivedTabs: original.archivedTabs,
            history: original.history,
            browsingPreferences: original.browsingPreferences,
            credentialPreferences: original.credentialPreferences,
            accessPolicy: original.accessPolicy,
            isSavedTabsExpanded: original.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: original.savedTabsExpansionModifiedAt
        )

        XCTAssertTrue(access.isLocked(replacement))
        let didUnlockReplacement = await access.unlock(replacement)
        XCTAssertTrue(didUnlockReplacement)
        XCTAssertEqual(authenticator.reasons.count, 2)
    }

    func testPrivateSpacesRelockWhenProtectedContentLeavesTheForeground() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(
            authenticator: BrowserDeviceAuthenticatorStub(results: [.success(true)])
        )
        let unlocked = await access.unlock(space)

        XCTAssertTrue(unlocked)
        access.lockAllForInactiveScene()

        XCTAssertTrue(access.isLocked(space))
    }

    func testAuthenticationCompletingAfterRelockCannotRevealTheSpace() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let authenticator = SuspendedBrowserDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let unlockTask = Task { await access.unlock(space) }
        await Task.yield()

        access.lockAll()
        authenticator.complete(with: true)
        let unlocked = await unlockTask.value

        XCTAssertFalse(unlocked)
        XCTAssertTrue(access.isLocked(space))
    }

    func testLockingAnotherSpaceDoesNotStrandAnAuthenticationInProgress() async throws {
        let spaces = BrowserSession.preview.spaces
        var authenticatingSpace = try XCTUnwrap(spaces.first)
        var otherSpace = try XCTUnwrap(spaces.dropFirst().first)
        authenticatingSpace.accessPolicy = .deviceOwnerAuthentication
        otherSpace.accessPolicy = .deviceOwnerAuthentication
        let authenticator = SuspendedBrowserDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let unlockTask = Task { await access.unlock(authenticatingSpace) }
        await Task.yield()

        access.lock(otherSpace.id)
        authenticator.complete(with: true)
        let unlocked = await unlockTask.value

        XCTAssertTrue(unlocked)
        XCTAssertFalse(access.isLocked(authenticatingSpace))
        XCTAssertNil(access.authenticatingAssignment)
    }

    func testSystemAuthenticationCanFinishAcrossTemporaryInactiveScene() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let authenticator = SuspendedBrowserDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let unlockTask = Task { await access.unlock(space) }
        await Task.yield()

        access.lockAllForInactiveScene()
        authenticator.complete(with: true)
        let unlocked = await unlockTask.value

        XCTAssertTrue(unlocked)
        XCTAssertFalse(access.isLocked(space))
    }

    func testDeniedAuthenticationNeverUnlocksAPrivateSpace() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(
            authenticator: BrowserDeviceAuthenticatorStub(results: [.success(false)])
        )

        let unlocked = await access.unlock(space)

        XCTAssertFalse(unlocked)
        XCTAssertTrue(access.isLocked(space))
        XCTAssertEqual(access.failure, .authenticationDenied)
    }

    func testPendingAuthenticationRejectsDuplicateAndOtherSpaceAttempts() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        var other = try XCTUnwrap(BrowserSession.preview.spaces.last)
        space.accessPolicy = .deviceOwnerAuthentication
        other.accessPolicy = .deviceOwnerAuthentication
        let authenticator = SuspendedBrowserDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let pending = Task { await access.unlock(space) }
        await Task.yield()

        let duplicate = await access.unlock(space)
        let otherAttempt = await access.unlock(other)

        XCTAssertFalse(duplicate)
        XCTAssertFalse(otherAttempt)
        XCTAssertTrue(access.isAuthenticating(space))
        XCTAssertFalse(access.isAuthenticating(other))
        XCTAssertTrue(access.isLocked(space))
        XCTAssertTrue(access.isLocked(other))
        XCTAssertEqual(authenticator.attemptCount, 1)
        authenticator.complete(with: true)
        let unlocked = await pending.value
        XCTAssertTrue(unlocked)
        XCTAssertTrue(access.isLocked(other))
    }

    func testUnavailableAuthenticationKeepsTheSpaceLockedAndAllowsRetry() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let authenticator = BrowserDeviceAuthenticatorStub(
            results: [.failure(CancellationError()), .success(true)]
        )
        let access = BrowserSpaceAccessController(authenticator: authenticator)

        let cancelled = await access.unlock(space)

        XCTAssertFalse(cancelled)
        XCTAssertTrue(access.isLocked(space))
        XCTAssertNil(access.authenticatingAssignment)
        XCTAssertEqual(access.failure, .authenticationUnavailable)

        let retried = await access.unlock(space)

        XCTAssertTrue(retried)
        XCTAssertNil(access.failure)
        XCTAssertNil(access.authenticatingAssignment)
        XCTAssertEqual(authenticator.reasons.count, 2)
    }

    func testStorePersistsDefaultAndPrivateSpacePolicies() throws {
        let store = BrowserStore(
            session: .preview,
            syncCoalescingDelay: .zero
        )
        let personal = try XCTUnwrap(store.session.spaces.last)

        store.setDefaultSpace(personal.id)
        store.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: personal.id)

        XCTAssertEqual(store.session.defaultSpaceID, personal.id)
        XCTAssertEqual(store.session.space(id: personal.id)?.accessPolicy, .deviceOwnerAuthentication)
    }

    func testAuthenticatedPolicyChangeCannotChangeAReplacementProfile() async throws {
        let store = BrowserStore(session: .preview)
        let otherWindow = store.makeWindowStore()
        let original = try XCTUnwrap(store.selectedSpace)
        store.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: original.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: original)
        let authenticator = SuspendedBrowserDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let update = Task { await access.updatePolicy(.open, matching: assignment, in: store) }
        while authenticator.attemptCount == 0 { await Task.yield() }
        let replacement = BrowserSpace(
            id: original.id, profile: BrowsingProfile(), name: "Replacement", symbol: original.symbol,
            accent: original.accent,
            folders: [], tabs: original.tabs, accessPolicy: .deviceOwnerAuthentication)
        otherWindow.session.spaces[0] = replacement

        authenticator.complete(with: true)
        let changed = await update.value

        XCTAssertFalse(changed)
        XCTAssertEqual(store.selectedSpace?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertTrue(access.isLocked(replacement))
    }

    func testRestoredWindowKeepsItsSpaceWhenTheDefaultSpaceDiffers() throws {
        var session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        session.defaultSpaceID = personal.id
        let root = BrowserStore(
            session: session
        )
        let savedState = BrowserWindowState(
            selectedSpaceID: work.id,
            selectedTabIDsBySpace: [:]
        )

        let window = root.makeWindowStore(restoring: savedState)

        XCTAssertEqual(window.selectedSpaceID, work.id)
        XCTAssertEqual(root.makeWindowStore().selectedSpaceID, personal.id)
    }
}

@MainActor
private final class BrowserDeviceAuthenticatorStub: BrowserDeviceAuthenticating {
    private var results: [Result<Bool, Error>]
    private(set) var reasons: [String] = []

    init(results: [Result<Bool, Error>]) {
        self.results = results
    }

    func authenticate(reason: String) async throws -> Bool {
        reasons.append(reason)
        return try results.removeFirst().get()
    }
}

@MainActor
private final class SuspendedBrowserDeviceAuthenticator: BrowserDeviceAuthenticating {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var attemptCount = 0

    func authenticate(reason: String) async throws -> Bool {
        attemptCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(with result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
