import XCTest

@testable import Crest

/// A one-time code is filled only for a row this launch issued, to the tab,
/// Space and origins it was issued for, within two minutes, and only once.
@MainActor
final class ApplePasswordsOneTimeCodesTests: XCTestCase {
    private let frame = CredentialOrigin(scheme: "https", host: "login.example.com", port: 443)
    private let top = CredentialOrigin(scheme: "https", host: "example.com", port: 443)
    private let other = CredentialOrigin(scheme: "https", host: "evil.example", port: 443)
    private let tab = UUID()
    private let space = UUID()
    private let support = ApplePasswordsTestSupport.available
    private var clock = Date(timeIntervalSince1970: 1_000)

    private func codes(_ source: FakeCodeSource) -> ApplePasswordsOneTimeCodes {
        ApplePasswordsOneTimeCodes(source: source, now: { [unowned self] in self.clock })
    }

    private func list(_ rows: ApplePasswordsOneTimeCodes, frame: CredentialOrigin? = nil, top: CredentialOrigin? = nil)
        async throws -> [BrowserOneTimeCodeSuggestion]
    {
        try await rows.rows(
            for: frame ?? self.frame, topLevelOrigin: top ?? self.top, in: space, username: nil, tab: tab,
            support: support)
    }

    private func fill(
        _ rows: ApplePasswordsOneTimeCodes, _ id: UUID, origin: CredentialOrigin? = nil,
        top: CredentialOrigin? = nil, space: UUID? = nil, tab: UUID?? = nil
    ) async throws -> String {
        try await rows.code(
            for: id, origin: origin ?? frame, topLevelOrigin: top ?? self.top, in: space ?? self.space,
            tab: tab ?? self.tab, support: support)
    }

    private func assertRefused(_ work: () async throws -> String, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        do {
            _ = try await work()
            XCTFail("The row must not fill.", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .notPermitted, file: file, line: line)
        }
    }

    func testACodeFillsOnlyForTheTabSpaceAndOriginsItWasIssuedTo() async throws {
        let source = FakeCodeSource(codes: [
            .init(source: .generated, code: "", username: "grace", domain: "login.example.com"),
            .init(source: .delivered, code: "123456", username: "ada", domain: "login.example.com"),
        ])
        let rows = codes(source)
        let issued = try await list(rows)
        XCTAssertEqual(issued.map(\.username), ["grace", "ada"])

        // Another frame, top-level page, Space, tab, or an unissued row reads nothing and asks nothing.
        await assertRefused { try await fill(rows, issued[0].id, origin: other) }
        await assertRefused { try await fill(rows, issued[0].id, top: other) }
        await assertRefused { try await fill(rows, issued[0].id, space: UUID()) }
        await assertRefused { try await fill(rows, issued[0].id, tab: .some(UUID())) }
        await assertRefused { try await fill(rows, issued[0].id, tab: .some(nil)) }
        await assertRefused { try await fill(rows, UUID()) }
        XCTAssertEqual(source.currentReads, 0)

        // A generated code is read after the pick, for the frame it was issued for.
        let generated = try await fill(rows, issued[0].id)
        XCTAssertEqual(generated, "654321")
        XCTAssertEqual(source.currentReads, 1)
        // A delivered code fills as it is, without asking the helper.
        let delivered = try await fill(rows, issued[1].id)
        XCTAssertEqual(delivered, "123456")
        XCTAssertEqual(source.currentReads, 1)
    }

    func testAPickConsumesItsRowAtOnceAndAFailureLeavesNewerRowsAlone() async throws {
        let source = FakeCodeSource(codes: [
            .init(source: .generated, code: "", username: "ada", domain: "login.example.com")
        ]
        )
        let rows = codes(source)
        let first = try await list(rows)

        // A second pick of the same row asks the helper nothing more.
        let picked = try await fill(rows, first[0].id)
        XCTAssertEqual(picked, "654321")
        await assertRefused { try await fill(rows, first[0].id) }
        XCTAssertEqual(source.currentReads, 1)

        // A failed read forgets that row only; a listing made since stays good.
        source.currentFails = true
        let older = try await list(rows)
        let newer = try await list(rows)
        await assertRefused { try await fill(rows, older[0].id) }
        source.currentFails = false
        let afterRefresh = try await fill(rows, newer[0].id)
        XCTAssertEqual(afterRefresh, "654321")

        let failing = try await list(rows)
        source.currentFails = true
        do {
            _ = try await fill(rows, failing[0].id)
            XCTFail("The helper failed.")
        } catch {
            XCTAssertEqual(error as? ApplePasswordsError, .loginNotFound)
        }
        await assertRefused { try await fill(rows, failing[0].id) }
    }

    func testARowExpiresAfterTwoMinutes() async throws {
        let source = FakeCodeSource(codes: [
            .init(source: .delivered, code: "123456", username: "ada", domain: "login.example.com")
        ])
        let rows = codes(source)
        let issued = try await list(rows)
        clock = clock.addingTimeInterval(ApplePasswordsOneTimeCodes.lifetime)
        let atTheLimit = try await fill(rows, issued[0].id)
        XCTAssertEqual(atTheLimit, "123456")

        let stale = try await list(rows)
        clock = clock.addingTimeInterval(ApplePasswordsOneTimeCodes.lifetime + 1)
        await assertRefused { try await fill(rows, stale[0].id) }
    }

    func testAFrameOutsideTheTopLevelPageGetsOnlyItsOwnSitesCodes() async throws {
        let source = FakeCodeSource(codes: [
            .init(source: .delivered, code: "111111", username: "ada", domain: "example.com"),
            .init(source: .delivered, code: "222222", username: "ada", domain: "https://LOGIN.example.com/x"),
            .init(source: .delivered, code: "333333", username: "ada", domain: nil),
            .init(source: .delivered, code: "444444", username: "ada", domain: "::bad::"),
        ])
        let rows = codes(source)

        let embedded = try await list(rows)
        XCTAssertEqual(embedded.count, 1)
        let code = try await fill(rows, embedded[0].id)
        XCTAssertEqual(code, "222222")

        // The top-level page itself keeps every entry.
        let samePage = try await list(rows, frame: top)
        XCTAssertEqual(samePage.count, 4)
    }

    func testADeliveredCodeWithoutAValueIsNeverIssued() async throws {
        let source = FakeCodeSource(codes: [
            .init(source: .delivered, code: "", username: "ada", domain: "login.example.com"),
            .init(source: .delivered, code: nil, username: "ada", domain: "login.example.com"),
            .init(source: .generated, code: "", username: "grace", domain: "login.example.com"),
        ])
        let issued = try await list(codes(source), frame: top)
        XCTAssertEqual(issued.map(\.username), ["grace"])
    }

    func testForgettingATabDropsItsRowsButNotAnotherTabs() async throws {
        let source = FakeCodeSource(codes: [
            .init(source: .delivered, code: "123456", username: "ada", domain: "login.example.com")
        ])
        let rows = codes(source)
        let mine = try await list(rows)
        let theirs = try await rows.rows(
            for: frame, topLevelOrigin: top, in: space, username: nil, tab: UUID(), support: support)
        XCTAssertEqual(theirs.count, 1)

        rows.forget(tab: tab)

        await assertRefused { try await fill(rows, mine[0].id) }
    }
}

@MainActor
private final class FakeCodeSource: ApplePasswordsCredentialSource {
    private let codes: [ApplePasswordsOneTimeCode]
    private(set) var currentReads = 0
    var currentFails = false
    private(set) var listedTopLevels: [CredentialOrigin] = []

    init(codes: [ApplePasswordsOneTimeCode]) {
        self.codes = codes
    }

    var canFillOneTimeCodes: Bool { true }

    func oneTimeCodes(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> [ApplePasswordsOneTimeCode] {
        listedTopLevels.append(topLevel)
        return codes
    }

    func currentOneTimeCode(
        for origin: CredentialOrigin, topLevel: CredentialOrigin, username: String?, domain: String?, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String {
        currentReads += 1
        if currentFails { throw ApplePasswordsError.loginNotFound }
        return "654321"
    }

    func logins(for origin: CredentialOrigin, tab: UUID?, support: ApplePasswordsSupport) async throws
        -> ApplePasswordsLoginNamesRequest.Logins
    {
        ApplePasswordsLoginNamesRequest.Logins(usernames: [], neverSaves: false)
    }

    func password(for origin: CredentialOrigin, username: String, tab: UUID?, support: ApplePasswordsSupport)
        async throws -> String
    {
        throw ApplePasswordsError.loginNotFound
    }
}
