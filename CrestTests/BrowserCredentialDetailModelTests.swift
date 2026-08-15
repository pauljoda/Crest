import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialDetailModelTests: XCTestCase {
    func testRevealForwardsExactCredentialAndRuntimeAssignment() async throws {
        let descriptor = try makeDescriptor()
        let assignment = makeAssignment(for: descriptor)
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "test-password"
        )
        var receivedCredentialID: CredentialID?
        var receivedAssignment: BrowserSpaceRuntimeAssignment?
        let model = makeModel(
            descriptor: descriptor,
            assignment: assignment,
            revealCredential: { credentialID, requestedAssignment, _ in
                receivedCredentialID = credentialID
                receivedAssignment = requestedAssignment
                return credential
            }
        )

        await model.toggleReveal()

        XCTAssertEqual(receivedCredentialID, descriptor.id)
        XCTAssertEqual(receivedAssignment, assignment)
        XCTAssertEqual(model.visiblePassword, "test-password")
        XCTAssertNotNil(model.revealExpiration)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertNil(model.errorMessage)

        await model.toggleReveal()

        XCTAssertNil(model.visiblePassword)
        XCTAssertNil(model.revealExpiration)
    }

    func testCopyWritesAnExpiringLocalLease() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "clipboard-password"
        )
        var writtenPassword: String?
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { _, _, _ in credential },
            writeClipboard: { lease in
                writtenPassword = lease.password(
                    at: Date(timeIntervalSince1970: 1_001)
                )
                return true
            }
        )

        await model.copy()

        XCTAssertEqual(writtenPassword, "clipboard-password")
        XCTAssertNotNil(model.copyExpiration)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertNil(model.errorMessage)
    }

    func testClipboardFailurePublishesUserFacingFailure() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "clipboard-password"
        )
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { _, _, _ in credential },
            writeClipboard: { _ in false }
        )

        await model.copy()

        XCTAssertNil(model.copyExpiration)
        XCTAssertEqual(
            model.errorMessage,
            String(localized: "Crest couldn’t copy that password.")
        )
        XCTAssertFalse(model.isAuthenticating)
    }

    func testAuthenticationFailureDoesNotExposeASecret() async throws {
        let descriptor = try makeDescriptor()
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { _, _, _ in throw TestError.expected }
        )

        await model.toggleReveal()

        XCTAssertNil(model.visiblePassword)
        XCTAssertEqual(
            model.errorMessage,
            String(
                localized: "Crest couldn’t authenticate and read that password from this Space."
            )
        )
        XCTAssertFalse(model.isAuthenticating)
    }

    func testClearingSensitiveStateRejectsLateRevealCompletion() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "must-not-appear"
        )
        let suspendedReveal = SuspendedReveal()
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { credentialID, assignment, reason in
                try await suspendedReveal.call(credentialID, assignment, reason)
            }
        )

        let task = Task { await model.toggleReveal() }
        await waitForInvocation(of: suspendedReveal)

        model.clearSensitiveState()
        suspendedReveal.resume(returning: credential)
        await task.value

        XCTAssertNil(model.visiblePassword)
        XCTAssertNil(model.revealExpiration)
        XCTAssertFalse(model.isAuthenticating)
    }

    func testDisappearanceRejectsALateCopyBeforeClipboardMutation() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "must-not-copy"
        )
        let suspendedReveal = SuspendedReveal()
        var clipboardWriteCount = 0
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { credentialID, assignment, reason in
                try await suspendedReveal.call(credentialID, assignment, reason)
            },
            writeClipboard: { _ in
                clipboardWriteCount += 1
                return true
            }
        )

        let task = Task { await model.copy() }
        await waitForInvocation(of: suspendedReveal)

        model.clearSensitiveState()
        suspendedReveal.resume(returning: credential)
        await task.value

        XCTAssertEqual(clipboardWriteCount, 0)
        XCTAssertNil(model.copyExpiration)
        XCTAssertFalse(model.isAuthenticating)
    }

    func testProfileReplacementRejectsRevealCompletion() async throws {
        let descriptor = try makeDescriptor()
        let assignment = makeAssignment(for: descriptor)
        var currentAssignment = assignment
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "old-profile-secret"
        )
        let suspendedReveal = SuspendedReveal()
        let model = makeModel(
            descriptor: descriptor,
            assignment: assignment,
            isAssignmentCurrent: { $0 == currentAssignment },
            revealCredential: { credentialID, assignment, reason in
                try await suspendedReveal.call(credentialID, assignment, reason)
            }
        )

        let task = Task { await model.toggleReveal() }
        await waitForInvocation(of: suspendedReveal)

        currentAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID,
            profileID: fixedUUID(3)
        )
        suspendedReveal.resume(returning: credential)
        await task.value

        XCTAssertNil(model.visiblePassword)
        XCTAssertNil(model.revealExpiration)
        XCTAssertFalse(model.isAuthenticating)
    }

    func testStaleRevealExpirationCannotClearANewerLease() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "newest-secret"
        )
        var now = Date(timeIntervalSince1970: 1_000)
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { _, _, _ in credential },
            now: { now }
        )

        await model.toggleReveal()
        let firstExpiration = try XCTUnwrap(model.revealExpiration)
        await model.toggleReveal()
        now = Date(timeIntervalSince1970: 2_000)
        await model.toggleReveal()
        let secondExpiration = try XCTUnwrap(model.revealExpiration)

        await model.expireReveal(at: firstExpiration)

        XCTAssertNotEqual(firstExpiration, secondExpiration)
        XCTAssertEqual(model.visiblePassword, "newest-secret")
        XCTAssertEqual(model.revealExpiration, secondExpiration)
    }

    func testConcurrentAuthenticationRequestIsIgnored() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "single-authentication"
        )
        let suspendedReveal = SuspendedReveal()
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { credentialID, assignment, reason in
                try await suspendedReveal.call(credentialID, assignment, reason)
            }
        )

        let firstTask = Task { await model.toggleReveal() }
        await waitForInvocation(of: suspendedReveal)
        await model.copy()

        XCTAssertEqual(suspendedReveal.invocationCount, 1)

        suspendedReveal.resume(returning: credential)
        await firstTask.value
        XCTAssertEqual(model.visiblePassword, "single-authentication")
    }

    func testCanceledExpirationTaskDoesNotClearCurrentReveal() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "still-visible"
        )
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { _, _, _ in credential },
            sleep: { _ in throw CancellationError() }
        )

        await model.toggleReveal()
        let expiration = try XCTUnwrap(model.revealExpiration)
        await model.expireReveal(at: expiration)

        XCTAssertEqual(model.visiblePassword, "still-visible")
        XCTAssertEqual(model.revealExpiration, expiration)
    }

    func testUnavailableAssignmentRejectsAuthenticationBeforeReading() async throws {
        let descriptor = try makeDescriptor()
        var revealCount = 0
        let model = makeModel(
            descriptor: descriptor,
            isAssignmentCurrent: { _ in false },
            revealCredential: { _, _, _ in
                revealCount += 1
                throw TestError.expected
            }
        )

        await model.toggleReveal()

        XCTAssertEqual(revealCount, 0)
        XCTAssertNil(model.visiblePassword)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertEqual(
            model.errorMessage,
            String(
                localized: "Crest couldn’t authenticate and read that password from this Space."
            )
        )
    }

    func testPresentationIdentityIncludesCredentialAndRuntimeAssignment() async throws {
        let descriptor = try makeDescriptor()
        let assignment = makeAssignment(for: descriptor)
        let original = BrowserCredentialDetailRequest(
            descriptor: descriptor,
            spaceAssignment: assignment,
            spaceName: "Original"
        )
        let replacement = BrowserCredentialDetailRequest(
            descriptor: descriptor,
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: assignment.spaceID,
                profileID: fixedUUID(9)
            ),
            spaceName: "Replacement"
        )

        XCTAssertNotEqual(original.id, replacement.id)
    }

    func testSensitiveAccessRejectsProfileReplacementDuringAuthentication() async throws {
        let browser = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .standard
        )
        let source = try XCTUnwrap(browser.session.spaces.first)
        let descriptor = try await browser.saveCredential(
            username: "person@example.com",
            password: "old-profile-secret",
            for: try XCTUnwrap(URL(string: "https://example.com/login")),
            in: source.id
        )
        let authenticator = SuspendedAuthenticator()
        let access = BrowserCredentialSensitiveAccess(
            browser: browser,
            authenticator: authenticator
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: source)

        let revealTask = Task {
            do {
                let credential = try await access.revealCredential(
                    id: descriptor.id,
                    matching: assignment
                )
                return Result<BrowserCredential, Error>.success(credential)
            } catch {
                return .failure(error)
            }
        }
        await waitForInvocation(of: authenticator)

        replaceProfile(of: source, in: browser)
        authenticator.resume()
        let result = await revealTask.value

        switch result {
        case .success:
            XCTFail("A replaced profile must not receive the captured credential")
        case .failure(let error):
            XCTAssertEqual(
                error as? BrowserCredentialSensitiveAccessError,
                .missingCredential
            )
        }
    }
}

extension BrowserCredentialDetailModelTests {
    @MainActor
    fileprivate final class SuspendedReveal {
        private(set) var invocationCount = 0
        private var continuation: CheckedContinuation<BrowserCredential, Error>?

        func call(
            _: CredentialID,
            _: BrowserSpaceRuntimeAssignment,
            _: String
        ) async throws -> BrowserCredential {
            invocationCount += 1
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func resume(returning credential: BrowserCredential) {
            continuation?.resume(returning: credential)
            continuation = nil
        }
    }

    fileprivate final class SuspendedAuthenticator: BrowserDeviceAuthenticating {
        private(set) var invocationCount = 0
        private var continuation: CheckedContinuation<Bool, Error>?

        func authenticate(reason _: String) async throws -> Bool {
            invocationCount += 1
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func resume() {
            continuation?.resume(returning: true)
            continuation = nil
        }
    }

    fileprivate enum TestError: Error {
        case expected
    }

    fileprivate func makeModel(
        descriptor: CredentialDescriptor,
        assignment: BrowserSpaceRuntimeAssignment? = nil,
        isAssignmentCurrent:
            @escaping @MainActor (
                BrowserSpaceRuntimeAssignment
            ) -> Bool = { _ in true },
        revealCredential: @escaping BrowserCredentialRevealer,
        writeClipboard: @escaping BrowserCredentialClipboardWriter = { _ in true },
        now: @escaping @MainActor () -> Date = {
            Date(timeIntervalSince1970: 1_000)
        },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { _ in }
    ) -> BrowserCredentialDetailModel {
        BrowserCredentialDetailModel(
            descriptor: descriptor,
            assignment: assignment ?? makeAssignment(for: descriptor),
            isAssignmentCurrent: isAssignmentCurrent,
            revealCredential: revealCredential,
            writeClipboard: writeClipboard,
            now: now,
            sleep: sleep
        )
    }

    fileprivate func makeAssignment(
        for descriptor: CredentialDescriptor
    ) -> BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: descriptor.spaceID,
            profileID: fixedUUID(2)
        )
    }

    fileprivate func makeDescriptor() throws -> CredentialDescriptor {
        let origin = try XCTUnwrap(
            CredentialOrigin(
                securityProtocol: "https",
                host: "example.com",
                port: 443
            )
        )
        return CredentialDescriptor(
            id: CredentialID(rawValue: fixedUUID(1)),
            spaceID: SpaceID(rawValue: fixedUUID(2)),
            origin: origin,
            username: "person@example.com",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    fileprivate func fixedUUID(_ byte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, byte
            )
        )
    }

    fileprivate func waitForInvocation(of revealer: SuspendedReveal) async {
        for _ in 0..<100 where revealer.invocationCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(revealer.invocationCount, 1)
    }

    fileprivate func waitForInvocation(of authenticator: SuspendedAuthenticator) async {
        for _ in 0..<100 where authenticator.invocationCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(authenticator.invocationCount, 1)
    }

    fileprivate func replaceProfile(of space: BrowserSpace, in browser: BrowserStore) {
        guard
            let index = browser.session.spaces.firstIndex(where: {
                $0.id == space.id
            })
        else {
            XCTFail("Expected the captured Space to remain available")
            return
        }
        let current = browser.session.spaces[index]
        browser.session.spaces[index] = BrowserSpace(
            id: current.id,
            profile: BrowsingProfile(id: fixedUUID(0x7F)),
            name: current.name,
            symbol: current.symbol,
            accent: current.accent,
            branding: current.branding,
            folders: current.folders,
            tabs: current.tabs,
            archivedTabs: current.archivedTabs,
            history: current.history,
            browsingPreferences: current.browsingPreferences,
            credentialPreferences: current.credentialPreferences,
            accessPolicy: current.accessPolicy,
            isSavedTabsExpanded: current.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: current.savedTabsExpansionModifiedAt,
            selectedTabID: current.selectedTabID
        )
    }
}
