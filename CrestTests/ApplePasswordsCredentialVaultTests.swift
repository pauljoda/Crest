import XCTest

@testable import Crest

/// The vault hands out a password only for an identifier it issued, and only
/// for the origin that identifier was issued for.
@MainActor
final class ApplePasswordsCredentialVaultTests: XCTestCase {
    private let spaceID = UUID()
    private let example = CredentialOrigin(scheme: "https", host: "example.com", port: 443)
    private let other = CredentialOrigin(scheme: "https", host: "other.example", port: 443)

    func testAPasswordIsReadOnlyForAnIdentifierTheVaultIssued() async throws {
        let source = FakeApplePasswordsSource(logins: [example: ["ada"]], passwords: [example: ["ada": "secret"]])
        let vault = ApplePasswordsCredentialVault(source: source, support: { _ in ApplePasswordsTestSupport.available })

        let unissued = try await vault.credential(id: UUID(), in: spaceID)
        XCTAssertNil(unissued)
        XCTAssertEqual(source.passwordReads, [])

        let descriptors = try await vault.descriptors(matching: example, in: spaceID)
        XCTAssertEqual(descriptors.map(\.username), ["ada"])
        XCTAssertEqual(source.passwordReads, [], "Listing reads no password.")

        let issued = try XCTUnwrap(descriptors.first)
        let credential = try await vault.credential(id: issued.id, in: spaceID)
        XCTAssertEqual(credential?.password, "secret")
        XCTAssertEqual(credential?.descriptor.origin, example)
        XCTAssertEqual(source.passwordReads, [FakeApplePasswordsSource.Read(origin: example, username: "ada")])
    }

    func testAnIdentifierBelongsToTheSpaceItWasIssuedFor() async throws {
        let source = FakeApplePasswordsSource(logins: [example: ["ada"]], passwords: [example: ["ada": "secret"]])
        let vault = ApplePasswordsCredentialVault(source: source, support: { _ in ApplePasswordsTestSupport.available })
        let descriptors = try await vault.descriptors(matching: example, in: spaceID)
        let descriptor = try XCTUnwrap(descriptors.first)

        let elsewhere = try await vault.credential(id: descriptor.id, in: UUID())
        XCTAssertNil(elsewhere)
        XCTAssertEqual(source.passwordReads, [])
    }

    func testAPasswordIsReadOnlyForTheOriginTheIdentifierWasIssuedFor() async throws {
        let source = FakeApplePasswordsSource(
            logins: [example: ["ada"], other: ["ada"]],
            passwords: [example: ["ada": "example-secret"], other: ["ada": "other-secret"]]
        )
        let vault = ApplePasswordsCredentialVault(source: source, support: { _ in ApplePasswordsTestSupport.available })
        let exampleDescriptors = try await vault.descriptors(matching: example, in: spaceID)
        let otherDescriptors = try await vault.descriptors(matching: other, in: spaceID)
        let forExample = try XCTUnwrap(exampleDescriptors.first)
        let forOther = try XCTUnwrap(otherDescriptors.first)
        XCTAssertNotEqual(forExample.id, forOther.id)

        let credential = try await vault.credential(id: forExample.id, in: spaceID)
        XCTAssertEqual(credential?.password, "example-secret")
        XCTAssertEqual(source.passwordReads.map(\.origin), [example])
    }

    func testAnOriginThatIsNotHttpsIsRefusedBeforeAnyHelperCall() async throws {
        let source = FakeApplePasswordsSource(logins: [:], passwords: [:])
        let vault = ApplePasswordsCredentialVault(source: source, support: { _ in ApplePasswordsTestSupport.available })
        let insecure = CredentialOrigin(scheme: "http", host: "example.com", port: 80)

        do {
            _ = try await vault.descriptors(matching: insecure, in: spaceID)
            XCTFail("An insecure origin must not be queried.")
        } catch {
            XCTAssertEqual(error as? CredentialVaultError, .insecureOrigin)
        }
        XCTAssertEqual(source.loginReads, 0)
    }

    func testTheHelperRefusesAnOriginThatIsNotHttpsBeforeAnyIO() async throws {
        let helper = ApplePasswordsHelper(launcher: RefusingLauncher())
        let insecure = CredentialOrigin(scheme: "http", host: "example.com", port: 80)

        do {
            _ = try await helper.logins(for: insecure, tab: nil, support: ApplePasswordsTestSupport.available)
            XCTFail("An insecure origin must not be queried.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .insecureOrigin)
        }
        do {
            _ = try await helper.password(
                for: insecure, username: "ada", tab: nil, support: ApplePasswordsTestSupport.available)
            XCTFail("An insecure origin must not be queried.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .insecureOrigin)
        }
        XCTAssertEqual(helper.state, .stopped)
    }
}

@MainActor
private final class FakeApplePasswordsSource: ApplePasswordsCredentialSource {
    struct Read: Equatable {
        let origin: CredentialOrigin
        let username: String
    }

    private let logins: [CredentialOrigin: [String]]
    private let passwords: [CredentialOrigin: [String: String]]
    private(set) var loginReads = 0
    private(set) var passwordReads: [Read] = []

    init(logins: [CredentialOrigin: [String]], passwords: [CredentialOrigin: [String: String]]) {
        self.logins = logins
        self.passwords = passwords
    }

    func logins(for origin: CredentialOrigin, tab: UUID?, support: ApplePasswordsSupport) async throws
        -> ApplePasswordsLoginNamesRequest.Logins
    {
        loginReads += 1
        return ApplePasswordsLoginNamesRequest.Logins(usernames: logins[origin] ?? [], neverSaves: false)
    }

    func password(for origin: CredentialOrigin, username: String, tab: UUID?, support: ApplePasswordsSupport)
        async throws -> String
    {
        passwordReads.append(Read(origin: origin, username: username))
        guard let password = passwords[origin]?[username] else { throw ApplePasswordsError.loginNotFound }
        return password
    }
}

extension FakeApplePasswordsSource {
    func oneTimeCodes(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> [ApplePasswordsOneTimeCode] { [] }

    func currentOneTimeCode(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, domain: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String { throw ApplePasswordsError.loginNotFound }

    var canFillOneTimeCodes: Bool { false }
}
