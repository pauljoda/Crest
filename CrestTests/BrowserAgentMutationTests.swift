import AppKit
import XCTest

@testable import Crest

/// Destructive tools preserve Space authority and native page-close semantics.
@MainActor
final class BrowserAgentMutationTests: XCTestCase {
    // MARK: - Actions - Mutations

    /// Deletion is explicit, scoped and idempotent, with live authorization checked before any history changes.
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
        await assertToolFailure(fixture, "delete_history", ["space": spaceArgument])
        await assertToolFailure(fixture, "delete_history", ["url": urlArgument])
        await assertToolFailure(
            fixture, "delete_history", ["space": spaceArgument, "url": .string("file:///tmp/history")])
        for inaccessible in [other.id, privateSpace.id, UUID()] {
            await assertToolFailure(
                fixture, "delete_history", ["space": .string(inaccessible.uuidString), "url": urlArgument])
        }
        XCTAssertTrue(fixture.space.history.entries.contains { $0.url == url.absoluteString })
        let deleted = try await fixture.invoke("delete_history", arguments)
        XCTAssertEqual(deleted["removed"], .number(1))
        XCTAssertEqual(deleted["space"], arguments["space"])
        XCTAssertFalse(fixture.space.history.entries.contains { $0.url == url.absoluteString })
        XCTAssertTrue(fixture.space.history.entries.contains { $0.url == kept.absoluteString })
        XCTAssertTrue(other.history.entries.contains { $0.url == url.absoluteString })
        XCTAssertTrue(privateSpace.history.entries.contains { $0.url == url.absoluteString })
        let repeated = try await fixture.invoke("delete_history", arguments)
        XCTAssertEqual(repeated["removed"], .number(0))
        browser.seedVisit(to: url, titled: "Protected", in: fixture.space.id)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: fixture.space.id)
        await assertToolFailure(fixture, "delete_history", arguments)
        browser.unlockForTesting(fixture.space.value.seed)
        browser.updateSpaceAccessPolicy(.open, in: fixture.space.id)
        let unlocked = try await fixture.invoke("search_history", ["query": .string("Protected")])
        XCTAssertEqual(try unlocked["entries"]?.decoded(as: [AgentJSON].self).count, 1)
        try fixture.core.send(AllowAgentSpace(spaceID: fixture.space.id, allowed: false))
        await assertToolFailure(fixture, "delete_history", arguments)
        try fixture.core.send(SetAgents(isOn: false))
        await assertToolFailure(fixture, "delete_history", arguments)
        XCTAssertTrue(fixture.space.history.entries.contains { $0.url == url.absoluteString })
    }

    /// Public close uses the native policy and releases the owning page without deleting durable tab identity.
    func testClosingTabsArchivesOrdinaryTabsAndPreservesDurablePages() async throws {
        for placement: TabPlacement in [.current, .saved, .pinned] {
            for policy in SavedTabClosePolicy.all where placement.isDurable || policy == .resumeLastLocation {
                let fixture = try BrowserAgentFixture()
                let opening = try await fixture.invoke("open_window", ["space": .string(fixture.space.id.uuidString)])
                let windowID = try XCTUnwrap(opening["windowID"]?.string.flatMap(UUID.init(uuidString:)))
                let window = try XCTUnwrap(fixture.application.windowCoordinator.existingModel(for: windowID))
                defer { fixture.windows.window(for: windowID)?.close() }
                let browser = window.browser
                let root = try XCTUnwrap(URL(string: "https://close.crest.test/root"))
                let tabID = try XCTUnwrap(browser.openNewTab(url: root, in: fixture.space.id, selecting: true))
                XCTAssertTrue(browser.moveTab(tabID, to: placement))
                let preferences = BrowserAppPreferenceStore()
                preferences.bind(to: browser, legacy: .unsaved)
                preferences.savedTabClosePolicy = policy
                let child = try XCTUnwrap(URL(string: "https://close.crest.test/child"))
                browser.seedSelectedTabNavigation(to: child, titled: "Changed last location")
                window.pages.select()
                XCTAssertTrue(window.pages.containsResidentPage(for: tabID))
                let original = try XCTUnwrap(fixture.space.tabs.model(tabID)).value.seed
                XCTAssertEqual(original.url, "https://close.crest.test/child")
                let archiveCount = fixture.space.archive.entries.count
                let answer = try await fixture.invoke("close_tab", ["tab": .string(tabID.uuidString)])
                XCTAssertEqual(answer["closed"], .bool(true))
                XCTAssertEqual(answer["tabPreserved"], .bool(placement.isDurable))
                if placement.isDurable {
                    var expected = original
                    if policy == .returnToSavedURL { expected.url = expected.savedURL ?? expected.url }
                    XCTAssertEqual(fixture.space.tabs.model(tabID)?.value.seed, expected)
                    XCTAssertEqual(fixture.space.archive.entries.count, archiveCount)
                } else {
                    XCTAssertFalse(fixture.space.tabs.contains(tabID))
                    XCTAssertTrue(fixture.space.archive.contains(tabID: tabID))
                }
                XCTAssertNotEqual(window.browser.shownTab?.id, tabID)
                XCTAssertFalse(window.pages.containsResidentPage(for: tabID))
                if placement.isDurable {
                    let reopened = try await fixture.invoke("show_tab", ["tab": .string(tabID.uuidString)])
                    XCTAssertEqual(reopened["tab"]?["id"], .string(tabID.uuidString))
                    XCTAssertTrue(window.pages.containsResidentPage(for: tabID))
                    let closedAgain = try await fixture.invoke("close_tab", ["tab": .string(tabID.uuidString)])
                    XCTAssertEqual(closedAgain["closed"], .bool(true))
                    XCTAssertFalse(window.pages.containsResidentPage(for: tabID))
                }
            }
        }
    }

    /// A deferred close must honor refusal and recheck access before a later approval commits it.
    func testDeferredDurableCloseReportsCompletionAndRechecksAuthorization() async throws {
        for (allowsClose, revokesAccess, locksSpace, stopsTab) in [
            (true, false, false, false), (false, false, false, false), (true, true, false, false),
            (true, false, true, false), (true, false, false, true),
        ] {
            let completes = allowsClose && !revokesAccess && !locksSpace && !stopsTab
            let fixture = try BrowserAgentFixture()
            let opening = try await fixture.invoke(
                "open_tab",
                [
                    "space": .string(fixture.space.id.uuidString),
                    "url": .string("https://close.crest.test/deferred"),
                ])
            let tabID = try XCTUnwrap(opening["tab"]?["id"]?.string.flatMap(UUID.init(uuidString:)))
            let browser = fixture.application.browser
            browser.saveTab(tabID)
            let original = try XCTUnwrap(fixture.space.tabs.model(tabID)).value.seed
            let gate = BrowserAgentFixture.DeferredDismissal()
            browser.family.pageDismissalAuthorizer = gate
            let closing = Task { try await fixture.invoke("close_tab", ["tab": .string(tabID.uuidString)]) }
            for _ in 0..<20 where gate.pending == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNotNil(gate.pending)
            if revokesAccess { try fixture.core.send(AllowAgentSpace(spaceID: fixture.space.id, allowed: false)) }
            if locksSpace {
                browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: fixture.space.id)
            }
            if stopsTab { try fixture.core.send(StopAgentTab(tabID: tabID)) }
            XCTAssertEqual(gate.resolve(allowsClose), completes)
            let answer = try await closing.value
            XCTAssertEqual(answer["closed"], .bool(completes))
            XCTAssertEqual(answer["tabPreserved"], .bool(true))
            XCTAssertEqual(fixture.space.tabs.model(tabID)?.value.seed, original)
            if !completes { XCTAssertNotNil(answer["note"]) }
        }
    }

    private func assertToolFailure(
        _ fixture: BrowserAgentFixture, _ name: String, _ arguments: [String: AgentJSON] = [:]
    )
        async
    {
        do {
            _ = try await fixture.invoke(name, arguments)
            XCTFail("The tool should refuse this operation.")
        } catch {}
    }
}
