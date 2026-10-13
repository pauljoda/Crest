import AppKit
import Darwin
import XCTest

@testable import Crest

/// Tools share the core's live permission boundary and never expose private tabs.
@MainActor
final class BrowserAgentCatalogTests: XCTestCase {
    private struct Visit: Decodable {
        let title: String
        let url: String
        let lastVisitedAt: String
    }

    private struct ClaimedTab: Decodable {
        let id: UUID
        let inUse: Bool
    }

    func testWindowToolsPreserveTheRequestedSpaceAndSavedTabIdentity() async throws {
        let fixture = try AgentFixture()
        let before = fixture.application.stackedWindowIDs
        await assertToolFailure(fixture, "open_window", ["url": .string("file:///private/tmp/test")])
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
        let opening = try await fixture.invoke(
            "open_window",
            [
                "space": .string(fixture.space.id.uuidString), "url": .string("https://example.com/window"),
            ])
        let windowID = try XCTUnwrap(opening["windowID"]?.string.flatMap(UUID.init(uuidString:)))
        defer { fixture.windows.window(for: windowID)?.close() }
        XCTAssertEqual(opening["spaceID"]?.string, fixture.space.id.uuidString)
        XCTAssertNotNil(opening["tabID"])
        let listed = try await fixture.invoke("list_tabs")
        let created = try XCTUnwrap(
            listed["tabs"]?.decoded(as: [ClaimedTab].self).first {
                $0.id.uuidString == opening["tabID"]?.string
            })
        XCTAssertTrue(created.inUse)
        let saved = try XCTUnwrap(fixture.space.tabs.models.first { $0.placement == .saved })
        let count = fixture.space.tabs.models.count
        let shown = try await fixture.invoke("show_tab", ["tab": .string(saved.id.uuidString)])
        XCTAssertEqual(shown["tab"]?["id"]?.string, saved.id.uuidString)
        XCTAssertEqual(fixture.space.tabs.models.count, count)
        let quick = try await fixture.invoke(
            "open_quick_window",
            [
                "space": .string(fixture.space.id.uuidString), "url": .string("https://example.com/quick"),
            ])
        let quickID = try XCTUnwrap(quick["windowID"]?.string.flatMap(UUID.init(uuidString:)))
        defer { fixture.windows.closeQuickWindowWithoutAsking(quickID) }
        XCTAssertNotNil(fixture.windows.quickWindow(quickID))
        XCTAssertNotEqual(quick["windowID"], opening["windowID"])
        XCTAssertEqual(quick["spaceID"], opening["spaceID"])
        let blank = try await fixture.invoke("open_blank_window", ["space": .string(fixture.space.id.uuidString)])
        XCTAssertEqual(blank["spaceID"], opening["spaceID"])
        let blankID = try XCTUnwrap(blank["windowID"]?.string.flatMap(UUID.init(uuidString:)))
        defer { fixture.windows.window(for: blankID)?.close() }
        XCTAssertNotNil(fixture.windows.window(for: blankID))
    }

    func testLiveHistoryAndProvidersRespectRevocationAndSearchBeforeLimiting() async throws {
        let fixture = try AgentFixture()
        let catalog = try await fixture.invoke("list_search_providers")
        XCTAssertNotNil(catalog["defaultProvider"])
        let url = try XCTUnwrap(URL(string: "https://docs.example.com/older"))
        fixture.application.browser.seedVisit(to: url, titled: "Older matching visit")
        for index in 0..<30 {
            fixture.application.browser.seedVisit(
                to: try XCTUnwrap(URL(string: "https://example.com/new/\(index)")), titled: "New visit")
        }
        let newest = try await fixture.invoke("search_history", ["limit": .number(25)])
        XCTAssertEqual(try newest["entries"]?.decoded(as: [Visit].self).count, 25)
        let found = try await fixture.invoke(
            "search_history", ["query": .string("Older matching"), "limit": .number(25)])
        let visits = try XCTUnwrap(found["entries"]?.decoded(as: [Visit].self))
        XCTAssertEqual(visits.map(\.url), ["https://docs.example.com/older"])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: try XCTUnwrap(visits.first?.lastVisitedAt)))
        let excluded = try await fixture.invoke("search_history", ["domain": .string("other.example.com")])
        XCTAssertEqual(try excluded["entries"]?.decoded(as: [Visit].self).count, 0)
        await assertToolFailure(fixture, "search_history", ["limit": .number(1001)])
        try fixture.core.send(AllowAgentSpace(spaceID: fixture.space.id, allowed: false))
        let revoked = try await fixture.invoke("search_history")
        XCTAssertEqual(try revoked["entries"]?.decoded(as: [Visit].self).count, 0)
        await assertToolFailure(fixture, "list_search_providers", ["space": .string(fixture.space.id.uuidString)])
    }

    func testPrivateCreationValidatesBeforeMutationAndNeverExposesPrivateTabs() async throws {
        let fixture = try AgentFixture()
        let before = fixture.application.stackedWindowIDs
        await assertToolFailure(fixture, "open_private_window", ["url": .string("javascript:alert(1)")])
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
        let answer = try await fixture.invoke("open_private_window", ["url": .string("https://example.com/private")])
        defer { fixture.application.closePrivateBrowsingWindow() }
        XCTAssertNotNil(answer["windowID"])
        XCTAssertNil(answer["tabID"])
        XCTAssertNil(answer["spaceID"])
        let tab = try XCTUnwrap(fixture.application.privateBrowser.shownTab)
        XCTAssertEqual(tab.url, "https://example.com/private")
        let listed = try await fixture.invoke("list_tabs")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(listed), as: UTF8.self).contains(tab.id.uuidString))
        await assertToolFailure(fixture, "show_tab", ["tab": .string(tab.id.uuidString)])
        fixture.application.privateBrowser.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/private")), titled: "Private history coverage")
        XCTAssertTrue(
            try XCTUnwrap(fixture.application.privateBrowser.shownSpace).history.entries.contains {
                $0.url == "https://example.com/private"
            })
        let history = try await fixture.invoke("search_history", ["query": .string("example.com/private")])
        XCTAssertEqual(try history["entries"]?.decoded(as: [Visit].self).count, 0)
        try fixture.core.send(SetAgents(isOn: false))
        await assertToolFailure(fixture, "open_private_window")
    }

    func testShowingSavedTabWithoutAnOpenWindowKeepsItsIdentity() async throws {
        let fixture = try AgentFixture()
        XCTAssertNil(fixture.windows.activeBrowserWindow)
        let saved = try XCTUnwrap(fixture.space.tabs.models.first { $0.placement == .saved })
        let count = fixture.space.tabs.models.count
        let shown = try await fixture.invoke("show_tab", ["tab": .string(saved.id.uuidString)])
        XCTAssertEqual(shown["tab"]?["id"]?.string, saved.id.uuidString)
        XCTAssertEqual(fixture.space.tabs.models.count, count)
        let window = try XCTUnwrap(fixture.windows.activeBrowserWindow)
        defer { window.close() }
    }

    func testDeniedSpacesCannotOpenPublicWindows() async throws {
        let fixture = try AgentFixture()
        try fixture.core.send(AllowAgentSpace(spaceID: fixture.space.id, allowed: false))
        let before = fixture.application.stackedWindowIDs
        for name in ["open_window", "open_blank_window", "open_quick_window"] {
            var arguments: [String: AgentJSON] = ["space": .string(fixture.space.id.uuidString)]
            if name != "open_blank_window" { arguments["url"] = .string("https://example.com/denied") }
            await assertToolFailure(fixture, name, arguments)
        }
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
        await assertToolFailure(fixture, "open_window")
    }

    func testLockedSpacesRedactListingsAndDenyPublicWindowCreation() async throws {
        let fixture = try AgentFixture()
        fixture.application.browser.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/locked-history")), titled: "Locked history coverage")
        let visible = try await fixture.invoke("search_history", ["query": .string("Locked history coverage")])
        XCTAssertEqual(try visible["entries"]?.decoded(as: [Visit].self).count, 1)
        fixture.application.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: fixture.space.id)
        let before = fixture.application.stackedWindowIDs
        let listing = try await fixture.invoke("list_spaces")
        let spaces = try XCTUnwrap(listing["spaces"]?.decoded(as: [AgentJSON].self))
        let locked = try XCTUnwrap(spaces.first { $0["id"]?.string == fixture.space.id.uuidString })
        XCTAssertEqual(locked["locked"], .bool(true))
        XCTAssertNil(locked["active"])
        XCTAssertNil(locked["symbol"])
        XCTAssertNil(locked["icon"])
        let history = try await fixture.invoke("search_history", ["query": .string("Locked history coverage")])
        XCTAssertEqual(try history["entries"]?.decoded(as: [Visit].self).count, 0)
        for name in ["open_window", "open_blank_window", "open_quick_window"] {
            var arguments: [String: AgentJSON] = ["space": .string(fixture.space.id.uuidString)]
            if name != "open_blank_window" { arguments["url"] = .string("https://example.com/locked") }
            await assertToolFailure(fixture, name, arguments)
        }
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
    }

    func testHistoryDomainMatchesSubdomainsButNotSiblingNamesAndIncludesMaps() async throws {
        let fixture = try AgentFixture()
        for address in [
            "https://example.com/root", "https://docs.example.com/sub", "https://notexample.com/no",
            "https://www.google.com/maps/place/test", "https://www.google.com/search?q=test",
        ] {
            fixture.application.browser.seedVisit(to: try XCTUnwrap(URL(string: address)), titled: "Domain coverage")
        }
        let answer = try await fixture.invoke(
            "search_history", ["query": .string("Domain coverage"), "domain": .string("example.com")])
        let visits = try XCTUnwrap(answer["entries"]?.decoded(as: [Visit].self))
        XCTAssertEqual(Set(visits.map(\.url)), ["https://example.com/root", "https://docs.example.com/sub"])
        let maps = try await fixture.invoke(
            "search_history", ["query": .string("Domain coverage"), "domain": .string("maps.google.com")])
        XCTAssertEqual(
            try maps["entries"]?.decoded(as: [Visit].self).map(\.url), ["https://www.google.com/maps/place/test"])
        await assertToolFailure(fixture, "search_history", ["limit": .number(0)])
    }

    private func assertToolFailure(_ fixture: AgentFixture, _ name: String, _ arguments: [String: AgentJSON] = [:])
        async
    {
        do {
            _ = try await fixture.invoke(name, arguments)
            XCTFail("The tool should refuse this operation.")
        } catch {}
    }
}

@MainActor
private final class AgentFixture {
    let host = WebKitShellHost()
    let application: BrowserMacApplication
    let windows: BrowserMacWindows
    let agents: BrowserMacAgents
    let link: BrowserMacAgents.Link
    let sessionID = UUID()
    let space: SpaceModel
    var core: CrestCore { application.browser.core }

    init() throws {
        application = try BrowserMacApplication()
        windows = BrowserMacWindows(application: application, engineHost: host)
        agents = BrowserMacAgents(application: application, windows: windows)
        space = try XCTUnwrap(application.browser.shownSpace)
        let identity = AgentIdentity(teamID: nil, signingID: nil, path: "/private/tmp/crest-test-agent", client: nil)
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EIO) }
        Darwin.close(descriptors[1])
        let peer = BrowserAgentPeer(helperProcessID: getpid(), agent: nil)
        link = BrowserMacAgents.Link(connection: BrowserAgentConnection(descriptor: descriptors[0], peer: peer))
        try core.send(SetAgents(isOn: true))
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
        try core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: "Test")))
        try core.send(BeginAgentSession(sessionID: sessionID, identity: identity, name: "Test"))
    }

    func invoke(_ name: String, _ arguments: [String: AgentJSON] = [:]) async throws -> AgentJSON {
        let tool = try XCTUnwrap(BrowserAgentTool.named(name))
        let answer = try await tool.perform(
            BrowserAgentCall(agents: agents, link: link, sessionID: sessionID, arguments: .object(arguments)))
        if answer.isError { throw BrowserAgentFailure(answer.content.first?.text ?? "The tool failed.") }
        let text = try XCTUnwrap(answer.content.first?.text)
        return try JSONDecoder().decode(AgentJSON.self, from: Data(text.utf8))
    }
}
