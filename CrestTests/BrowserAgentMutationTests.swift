import AppKit
import XCTest

@testable import Crest

/// Deleting history stays inside the Space the agent may reach and happens
/// only once the person agrees.
@MainActor
final class BrowserAgentMutationTests: XCTestCase {
    // MARK: - Actions - Mutations

    /// Deletion is scoped and idempotent, asks the person only about an address
    /// the Space has visited, and checks access before asking and again after.
    func testHistoryDeletionPreservesOtherSpacesAndRejectsUnavailableReach() async throws {
        let fixture = try BrowserAgentFixture()
        let browser = fixture.application.browser
        let url = try XCTUnwrap(URL(string: "https://history.crest.test/target"))
        let kept = try XCTUnwrap(URL(string: "https://history.crest.test/keep"))
        browser.seedVisit(to: url, titled: "Delete", in: fixture.space.id)
        browser.seedVisit(to: kept, titled: "Keep", in: fixture.space.id)
        browser.addSpace()
        let other = try XCTUnwrap(browser.shownSpace)
        browser.seedVisit(to: url, titled: "Other Space", in: other.id)
        fixture.windows.openPrivateWindow()
        defer { fixture.application.closePrivateBrowsingWindow() }
        let privateSpace = try XCTUnwrap(fixture.application.privateBrowser.shownSpace)
        fixture.application.privateBrowser.seedVisit(to: url, titled: "Private")
        let spaceArgument = AgentJSON.string(fixture.space.id.uuidString)
        let urlArgument = AgentJSON.string(url.absoluteString + "#section")
        let arguments: [String: AgentJSON] = ["space": spaceArgument, "url": urlArgument]
        await fixture.assertRefused("delete_history", ["space": spaceArgument])
        await fixture.assertRefused("delete_history", ["url": urlArgument])
        await fixture.assertRefused(
            "delete_history", ["space": spaceArgument, "url": .string("file:///tmp/history")])
        for inaccessible in [other.id, privateSpace.id, UUID()] {
            await fixture.assertRefused(
                "delete_history", ["space": .string(inaccessible.uuidString), "url": urlArgument])
        }
        XCTAssertTrue(fixture.space.history.entries.contains { $0.url == url.absoluteString })
        XCTAssertEqual(fixture.answers.deletions, [])
        fixture.answers.deletesHistory = false
        await fixture.assertRefused("delete_history", arguments)
        XCTAssertTrue(fixture.space.history.entries.contains { $0.url == url.absoluteString })
        fixture.answers.deletesHistory = true
        let deleted = try await fixture.invoke("delete_history", arguments)
        XCTAssertEqual(deleted["removed"], .number(1))
        XCTAssertEqual(deleted["space"], arguments["space"])
        XCTAssertEqual(fixture.answers.deletions.map(\.agentName), ["Test", "Test"])
        XCTAssertEqual(fixture.answers.deletions.map(\.address), [url.absoluteString, url.absoluteString])
        XCTAssertFalse(fixture.space.history.entries.contains { $0.url == url.absoluteString })
        XCTAssertTrue(fixture.space.history.entries.contains { $0.url == kept.absoluteString })
        XCTAssertTrue(other.history.entries.contains { $0.url == url.absoluteString })
        XCTAssertTrue(privateSpace.history.entries.contains { $0.url == url.absoluteString })
        let repeated = try await fixture.invoke("delete_history", arguments)
        XCTAssertEqual(repeated["removed"], .number(0))
        XCTAssertEqual(fixture.answers.deletions.count, 2)
        browser.seedVisit(to: url, titled: "Protected", in: fixture.space.id)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: fixture.space.id)
        await fixture.assertRefused("delete_history", arguments)
        browser.unlockForTesting(fixture.space.value.seed)
        browser.updateSpaceAccessPolicy(.open, in: fixture.space.id)
        let unlocked = try await fixture.invoke("search_history", ["query": .string("Protected")])
        XCTAssertEqual(try unlocked["entries"]?.decoded(as: [AgentJSON].self).count, 1)
        try fixture.core.send(AllowAgentSpace(spaceID: fixture.space.id, allowed: false))
        await fixture.assertRefused("delete_history", arguments)
        try fixture.core.send(SetAgents(isOn: false))
        await fixture.assertRefused("delete_history", arguments)
        XCTAssertTrue(fixture.space.history.entries.contains { $0.url == url.absoluteString })
    }
}
