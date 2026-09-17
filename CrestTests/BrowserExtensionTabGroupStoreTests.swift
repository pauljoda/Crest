import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionTabGroupStoreTests: XCTestCase {
    private let claude = BrowserExtensionServiceClientID("claude")!
    private let chatgpt = BrowserExtensionServiceClientID("chatgpt")!

    func testMembershipEventsAreOrderedSeparateFromVisualEventsAndSpaceIsolated() async throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let store = browser.extensionTabGroups
        store.register(client: claude, spaceID: space.id)
        let stream = store.membershipEvents(for: claude)
        let group = try store.group([space.tabs[0].id], in: space.id, into: nil)
        _ = try store.group([space.tabs[1].id], in: space.id, into: group.id)
        _ = try store.update(group.id, in: space.id, title: "Renamed", color: .orange, isCollapsed: nil)
        store.ungroup([space.tabs[0].id], in: space.id)
        let other = browser.session.spaces[1]
        _ = try store.group([other.tabs[0].id], in: other.id, into: nil)
        browser.session.spaces[0].tabs.removeAll { $0.id == space.tabs[1].id }
        browser.persist(scope: .core)
        store.unregister(client: claude)
        var received: [BrowserExtensionTabGroupEvent.Membership] = []
        for await event in stream { received.append(event) }
        XCTAssertEqual(received.map(\.spaceID), [space.id, space.id, space.id])
        XCTAssertEqual(
            received.flatMap(\.changes).map(\.tabID), [space.tabs[0].id, space.tabs[1].id, space.tabs[0].id])
        XCTAssertEqual(received.flatMap(\.changes).map(\.groupID), [group.id, group.id, nil])
    }

    func testMembershipWatchDoesNotRequireSensitiveTabOrGroupPermission() async throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        browser.extensionTabGroups.register(client: claude, spaceID: space.id)
        var messages: [[String: Any]] = []
        let changed = expectation(description: "Membership changed")
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(clientID: claude, allowsInternalCapabilityBroker: true),
            notificationService: nil, idleStateProvider: { _ in .active },
            webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry(),
            tabGroupService: browser.extensionTabGroups,
            publish: { message in
                messages.append(message)
                if !(message["changes"] as? [[String: Any]] ?? []).isEmpty { changed.fulfill() }
            })
        defer { connection.stop() }
        try connection.receive(["api": "tabs.watchMembership"])
        let group = try browser.extensionTabGroups.group([space.tabs[0].id], in: space.id, into: nil)
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(messages.count, 2, "The connection acknowledges readiness and then delivers the actual change.")
        let change = try XCTUnwrap((messages.last?["changes"] as? [[String: Any]])?.first)
        XCTAssertEqual(change["tabToken"] as? String, space.tabs[0].id.rawValue.uuidString)
        XCTAssertEqual(change["groupId"] as? Int, group.id.rawValue)
        XCTAssertNil(change["url"])
        XCTAssertNil(change["title"])
    }

    func testUngroupBrokerReconcilesTabOrderBeforeReturningRemainingMembership() async throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let store = browser.extensionTabGroups
        let grouped = Array(space.tabs.prefix(2).map(\.id))
        let group = try store.group(grouped, in: space.id, into: nil)
        let coordinator = BrowserExtensionTabWindowCoordinator()
        coordinator.browser = browser
        coordinator.tabGroupService = store
        coordinator.reconcileCurrentSession()
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        coordinator.register(controller: controller, spaceID: space.id)
        defer { coordinator.unregister(spaceID: space.id) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/DebuggerAgentProbeExtension", directoryHint: .isDirectory)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: fixture))
        try controller.load(context)
        defer { try? controller.unload(context) }
        coordinator.registerCapabilityBrokerAuthorization(
            .init(clientID: claude, allowsInternalCapabilityBroker: true), for: context)
        let before = try XCTUnwrap(coordinator.currentState?.space(space.id))
        let target = try XCTUnwrap(before.tabs.first { $0.id == grouped[0] })
        var reply: [String: Any]?
        var failure: (any Error)?
        XCTAssertTrue(
            coordinator.handleCapabilityBrokerTabGroups(
                ["api": "tabs.ungroup", "tabs": [["tabIndex": target.index]]],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
                controller: controller, extensionContext: context,
                replyHandler: { value, error in
                    reply = value as? [String: Any]
                    failure = error
                }))
        XCTAssertNil(failure)
        let expected = try XCTUnwrap(BrowserExtensionSessionState(session: browser.session).space(space.id))
        XCTAssertNotEqual(before.tabs.map(\.id), expected.tabs.map(\.id), "The fixture must change tab indices.")
        XCTAssertEqual(coordinator.currentState?.space(space.id)?.tabs.map(\.id), expected.tabs.map(\.id))
        XCTAssertEqual(coordinator.lastState?.space(space.id)?.tabs.map(\.id), expected.tabs.map(\.id))
        let remaining = try XCTUnwrap(expected.tabs.first { $0.id == grouped[1] })
        let membership = try XCTUnwrap(reply?["membership"] as? [[String: Int]])
        XCTAssertEqual(membership, [["tabIndex": remaining.index, "groupId": group.id.rawValue]])
    }

    func testGroupsProjectTheSameFoldersForEveryExtensionAndStayInsideTheirSpace() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let personal = browser.session.spaces[1]
        let store = browser.extensionTabGroups
        store.register(client: claude, spaceID: space.id)
        store.register(client: chatgpt, spaceID: space.id)
        let created = try store.group([space.tabs[0].id], in: space.id, into: nil)
        let updated = try store.update(created.id, in: space.id, title: "Research", color: .orange, isCollapsed: true)
        XCTAssertEqual(updated.title, "Research")
        XCTAssertEqual(store.membership(in: space.id), [space.tabs[0].id: created.id])
        XCTAssertEqual(browser.session.spaces[0].folders.first?.title, "Research")
        XCTAssertEqual(browser.session.spaces[0].folders.first?.color, BrowserExtensionTabGroupColor.orange.brandColor)
        XCTAssertThrowsError(try store.group(created.id, in: personal.id))
        XCTAssertTrue(store.groups(in: personal.id).isEmpty)
        XCTAssertEqual(store.space(for: chatgpt), space.id)
    }

    func testMembershipDoesNotMasqueradeAsVisualUpdateAndAnEmptiedGroupIDIsNotReused() async throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let store = browser.extensionTabGroups
        store.register(client: claude, spaceID: space.id)
        let group = try store.group([space.tabs[0].id], in: space.id, into: nil)
        var events = store.events(for: claude).makeAsyncIterator()
        _ = try store.group([space.tabs[1].id], in: space.id, into: group.id)
        _ = try store.update(group.id, in: space.id, title: nil, color: .cyan, isCollapsed: nil)
        let updated = await events.next()
        XCTAssertEqual(updated?.kind, .updated)
        XCTAssertEqual(updated?.group.color, .cyan)
        store.ungroup(Array(space.tabs.prefix(2).map(\.id)), in: space.id)
        let removed = await events.next()
        XCTAssertEqual(removed?.kind, .removed)
        XCTAssertEqual(removed?.group.id, group.id)
        XCTAssertTrue(store.groups(in: space.id).isEmpty)
        XCTAssertFalse(browser.session.spaces[0].folders.contains { $0.id == group.folderID })
        let next = try store.group([space.tabs[2].id], in: space.id, into: nil)
        XCTAssertGreaterThan(next.id.rawValue, group.id.rawValue)
        let created = await events.next()
        XCTAssertEqual(created?.kind, .created)
    }

    func testGroupingValidatesBeforeMutatingAndCannotStealPinnedOrForeignTabs() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let store = browser.extensionTabGroups
        let original = try store.group([space.tabs[0].id], in: space.id, into: nil)
        let before = browser.session
        XCTAssertThrowsError(try store.group([space.tabs[0].id], in: space.id, into: .init(rawValue: 9999)))
        XCTAssertThrowsError(try store.group([browser.session.spaces[1].tabs[0].id], in: space.id, into: nil))
        XCTAssertThrowsError(try store.group([], in: space.id, into: nil))
        XCTAssertEqual(browser.session, before)
        XCTAssertEqual(store.membership(in: space.id)[space.tabs[0].id], original.id)
        _ = browser.moveTab(space.tabs[1].id, to: .pinned)
        XCTAssertThrowsError(try store.group([space.tabs[1].id], in: space.id, into: nil))
    }

    func testRestoredExtensionRegroupingDoesNotAccumulateEmptyCurrentFolders() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let tabID = space.tabs[0].id
        let store = browser.extensionTabGroups
        let first = try store.group([tabID], in: space.id, into: nil)
        _ = try store.update(first.id, in: space.id, title: "Claude", color: .orange, isCollapsed: nil)
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        let relaunched = BrowserStore(session: restored, persistence: InMemoryBrowserSessionPersistence())
        let untouched = try XCTUnwrap(relaunched.session.addFolder(title: "Keep", location: .current, in: space.id))
        relaunched.persist(scope: .core)
        let groups = relaunched.extensionTabGroups
        // A worker's saved native tab/group IDs may no longer match after a
        // browser restart. Claude ungroups and regroups the restored tab.
        groups.ungroup([tabID], in: space.id)
        let replacement = try groups.group([tabID], in: space.id, into: nil)
        _ = try groups.update(replacement.id, in: space.id, title: "Claude", color: .orange, isCollapsed: nil)
        let folders = try XCTUnwrap(relaunched.session.space(id: space.id)).folders
        XCTAssertEqual(folders.filter { $0.title == "Claude" }.map(\.id), [replacement.folderID])
        XCTAssertTrue(folders.contains { $0.id == untouched })
        XCTAssertFalse(folders.contains { $0.id == first.folderID })
        XCTAssertEqual(groups.membership(in: space.id)[tabID], replacement.id)
    }

    func testGroupIdentitySurvivesMovingItsFolderBetweenSavedAndCurrent() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let store = browser.extensionTabGroups
        let group = try store.group([space.tabs[0].id], in: space.id, into: nil)
        XCTAssertTrue(browser.moveFolder(group.folderID, matching: .init(space: space), to: .saved))
        XCTAssertEqual(try store.group(group.id, in: space.id).folderID, group.folderID)
        XCTAssertEqual(store.membership(in: space.id)[space.tabs[0].id], group.id)
        XCTAssertTrue(browser.moveFolder(group.folderID, matching: .init(space: space), to: .current))
        XCTAssertEqual(try store.group(group.id, in: space.id).folderID, group.folderID)
    }

    func testClosingTabsAndUnregisteringClientsPreserveOrdinaryFolderState() async throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let store = browser.extensionTabGroups
        store.register(client: claude, spaceID: space.id)
        let group = try store.group([space.tabs[0].id], in: space.id, into: nil)
        var events = store.events(for: claude).makeAsyncIterator()
        browser.session.spaces[0].tabs.removeFirst()
        browser.persist(scope: .core)
        let removed = await events.next()
        XCTAssertEqual(removed?.kind, .removed)
        XCTAssertEqual(removed?.group.id, group.id)
        XCTAssertTrue(browser.session.spaces[0].folders.contains { $0.id == group.folderID })
        store.unregister(client: claude)
        let finished = await events.next()
        XCTAssertNil(finished)
    }

    private func makeBrowser() -> BrowserStore {
        let spaces = (1...2).map { i in
            var space = BrowserSession.makeBlankSpace(number: i)
            space.tabs = (0..<3).map { n in
                BrowserTab(title: "Page \(n)", url: URL(string: "https://example.com/\(n)"), placement: .current)
            }
            space.selectedTabID = space.tabs[0].id
            return space
        }
        return BrowserStore(
            session: .init(spaces: spaces, selectedSpaceID: spaces[0].id),
            persistence: InMemoryBrowserSessionPersistence())
    }
}
