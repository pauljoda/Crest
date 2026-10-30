import XCTest

@testable import Crest

@MainActor
final class BrowserSettingsPrivacyPolicyTests: XCTestCase {
    func testCredentialMetadataLoadsOnlyWhilePrivateSpaceIsUnlocked() async throws {
        var session = SessionState.Seed.preview
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let space = session.spaces[0]
        let browser = BrowserStore(
            seed: session,
            credentialVault: InMemoryCredentialVault()
        )
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        _ = try await browser.saveCredential(
            username: "private-user",
            password: "private-secret",
            for: url,
            in: space.id
        )
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )
        browser.attachSpaceAccess(access)
        let credentials = BrowserCredentialSpaceStore(browser: browser)

        await credentials.load(in: space.id, accessController: access)

        XCTAssertTrue(credentials.descriptors.isEmpty)

        let unlocked = await access.unlock(try XCTUnwrap(browser.spaceModel(space.id)))

        XCTAssertTrue(unlocked)
        await credentials.load(in: space.id, accessController: access)

        XCTAssertEqual(credentials.descriptors.map(\.username), ["private-user"])

        access.lock(space.id)
        await credentials.load(in: space.id, accessController: access)

        XCTAssertTrue(credentials.descriptors.isEmpty)
    }

    /// Switching Space cancels the load SwiftUI started for the old one, but the
    /// Keychain read it is in does not stop. When that read lands after the new
    /// Space's, it must neither replace the new list nor empty it.
    func testSupersededSpaceLoadLeavesTheSelectedSpaceAlone() async throws {
        let session = SessionState.Seed.preview
        let first = session.spaces[0]
        let second = session.spaces[1]
        let vault = GatedCredentialVault()
        let browser = BrowserStore(seed: session, credentialVault: vault)
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        _ = try await browser.saveCredential(
            username: "first-user", password: "first-secret", for: url, in: first.id)
        _ = try await browser.saveCredential(
            username: "second-user", password: "second-secret", for: url, in: second.id)
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )
        browser.attachSpaceAccess(access)
        let credentials = BrowserCredentialSpaceStore(browser: browser)

        let firstLoad = Task { await credentials.load(in: first.id, accessController: access) }
        await vault.waitForListing(in: first.id)
        firstLoad.cancel()
        let secondLoad = Task { await credentials.load(in: second.id, accessController: access) }
        await vault.waitForListing(in: second.id)

        await vault.release(second.id)
        await secondLoad.value

        XCTAssertEqual(credentials.descriptors.map(\.username), ["second-user"])
        XCTAssertFalse(credentials.isLoading)

        await vault.release(first.id)
        await firstLoad.value

        XCTAssertEqual(credentials.descriptors.map(\.username), ["second-user"])
        XCTAssertFalse(credentials.isLoading)
    }
}

/// An in-memory vault whose Space listings wait at a gate until the test
/// releases them, so two loads can land in a chosen order.
private actor GatedCredentialVault: CredentialVault {
    private let inner = InMemoryCredentialVault()
    private var gates: [UUID: CheckedContinuation<Void, Never>] = [:]

    func descriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        await withCheckedContinuation { gates[spaceID] = $0 }
        return await inner.descriptors(in: spaceID)
    }

    /// Returns once the listing of `spaceID` is waiting at its gate.
    func waitForListing(in spaceID: UUID) async {
        while gates[spaceID] == nil { await Task.yield() }
    }

    func release(_ spaceID: UUID) {
        gates.removeValue(forKey: spaceID)?.resume()
    }

    func descriptors(matching origin: CredentialOrigin, in spaceID: UUID) async throws -> [CredentialDescriptor] {
        await inner.descriptors(matching: origin, in: spaceID)
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace, in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        await inner.descriptors(matching: protectionSpace, in: spaceID)
    }

    func unreadableCredentialCount(in spaceID: UUID) async throws -> Int {
        await inner.unreadableCredentialCount(in: spaceID)
    }

    func credential(id: UUID, in spaceID: UUID) async throws -> BrowserCredential? {
        await inner.credential(id: id, in: spaceID)
    }

    func save(_ credential: BrowserCredential, in spaceID: UUID) async throws {
        try await inner.save(credential, in: spaceID)
    }

    func replaceAll(_ credentials: [BrowserCredential], in spaceID: UUID) async throws {
        try await inner.replaceAll(credentials, in: spaceID)
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: UUID) async throws {
        await inner.setSynchronizable(isSynchronizable, in: spaceID)
    }

    func delete(id: UUID, in spaceID: UUID) async throws {
        await inner.delete(id: id, in: spaceID)
    }

    func deleteAll(in spaceID: UUID) async throws {
        await inner.deleteAll(in: spaceID)
    }

    func deleteUnreadableCredentials(in spaceID: UUID) async throws {
        await inner.deleteUnreadableCredentials(in: spaceID)
    }
}

@MainActor
private final class SettingsPrivacyAuthenticatorStub: BrowserDeviceAuthenticating {
    let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func authenticate(reason: String) async throws -> Bool {
        result
    }
}
