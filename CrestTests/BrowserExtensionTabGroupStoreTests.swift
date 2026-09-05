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

    func testIdentityRevisionDetectsMovingUngroupedTabsAwayAndBack() {
        let browser = makeBrowser()
        let store = browser.extensionTabGroups
        let before = browser.session
        let revision = store.revision
        browser.session.spaces[0].tabs.swapAt(0, 1)
        browser.persist(scope: .core)
        XCTAssertGreaterThan(store.revision, revision)
        let movedRevision = store.revision
        browser.session = before
        browser.persist(scope: .core)
        XCTAssertGreaterThan(store.revision, movedRevision)
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

    func testUIChangesPublishToSharedSpaceClientsAndNeverAcrossSpaces() async throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let personal = browser.session.spaces[1]
        let store = browser.extensionTabGroups
        let outsider = BrowserExtensionServiceClientID("outsider")!
        store.register(client: claude, spaceID: space.id)
        store.register(client: chatgpt, spaceID: space.id)
        store.register(client: outsider, spaceID: personal.id)
        var first = store.events(for: claude).makeAsyncIterator()
        var second = store.events(for: chatgpt).makeAsyncIterator()
        var third = store.events(for: outsider).makeAsyncIterator()
        let folder = try XCTUnwrap(browser.createTabFolder([space.tabs[0].id], in: space.id))
        let created = await first.next()
        let shared = await second.next()
        XCTAssertEqual(created?.kind, .created)
        XCTAssertEqual(created, shared)
        XCTAssertEqual(created?.group.folderID, folder)
        _ = browser.renameFolder(folder, in: space.id, title: "Docs")
        let updated = await first.next()
        XCTAssertEqual(updated?.kind, .updated)
        XCTAssertEqual(updated?.group.title, "Docs")
        let unrelated = try store.group([personal.tabs[0].id], in: personal.id, into: nil)
        let outside = await third.next()
        XCTAssertEqual(outside?.group.id, unrelated.id)
        XCTAssertEqual(outside?.kind, .created)
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
        XCTAssertTrue(browser.session.spaces[0].folders.contains { $0.id == group.folderID })
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

    func testSavedTabCanEstablishAnExtensionGroupWithoutLosingSavedPlacement() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let tabID = space.tabs[0].id
        _ = browser.moveTab(tabID, to: .saved)
        let savedURL = browser.session.spaces[0].tabs.first { $0.id == tabID }?.savedURL
        let store = browser.extensionTabGroups
        let group = try store.group([tabID], in: space.id, into: nil)
        _ = try store.update(group.id, in: space.id, title: "Claude", color: .orange, isCollapsed: false)
        let folder = try XCTUnwrap(browser.session.spaces[0].folders.first { $0.id == group.folderID })
        XCTAssertEqual(folder.location, .saved)
        XCTAssertEqual(folder.title, "Claude")
        XCTAssertEqual(store.membership(in: space.id)[tabID], group.id)
        store.ungroup([tabID], in: space.id)
        let ungrouped = try XCTUnwrap(browser.session.spaces[0].tabs.first { $0.id == tabID })
        XCTAssertEqual(ungrouped.placement, .saved)
        XCTAssertEqual(ungrouped.savedURL, savedURL)
        XCTAssertNil(ungrouped.folderID)
        XCTAssertNil(store.membership(in: space.id)[tabID])
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

    func testAddingToSavedGroupUsesTheExistingFoldersPlacement() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        _ = browser.moveTab(space.tabs[0].id, to: .saved)
        let store = browser.extensionTabGroups
        let group = try store.group([space.tabs[0].id], in: space.id, into: nil)
        _ = try store.group([space.tabs[1].id], in: space.id, into: group.id)
        let members = browser.session.spaces[0].tabs.filter { $0.folderID == group.folderID }
        XCTAssertEqual(Set(members.map(\.id)), Set(space.tabs.prefix(2).map(\.id)))
        XCTAssertTrue(members.allSatisfy { $0.placement == .saved })
        XCTAssertEqual(Set(store.membership(in: space.id).values), [group.id])
    }

    func testMovingSavedGroupReordersItsFolderAndNativeTabsWithoutDemotingIt() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let ids = space.tabs.map(\.id)
        for id in ids { _ = browser.moveTab(id, to: .saved) }
        let store = browser.extensionTabGroups
        let first = try store.group([ids[0]], in: space.id, into: nil)
        let second = try store.group([ids[1], ids[2]], in: space.id, into: nil)
        _ = try store.move(second.id, in: space.id, to: 0)
        XCTAssertEqual(browser.session.spaces[0].tabs.map(\.id), [ids[1], ids[2], ids[0]])
        XCTAssertEqual(browser.session.spaces[0].folders.map(\.id), [second.folderID, first.folderID])
        XCTAssertTrue(browser.session.spaces[0].tabs.allSatisfy { $0.placement == .saved })
        _ = try store.move(second.id, in: space.id, to: -1)
        XCTAssertEqual(browser.session.spaces[0].tabs.map(\.id), ids)
        XCTAssertEqual(browser.session.spaces[0].folders.map(\.id), [first.folderID, second.folderID])
        XCTAssertTrue(browser.session.spaces[0].tabs.allSatisfy { $0.placement == .saved })
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

    func testCustomFolderColorIsPreservedWhileTheAPIUsesItsNearestPaletteColor() throws {
        let browser = makeBrowser()
        let space = browser.session.spaces[0]
        let color = BrowserSpaceBrandColor(red: 0.031, green: 0.51, blue: 0.99)
        let folder = try XCTUnwrap(browser.createTabFolder([space.tabs[0].id], in: space.id))
        _ = browser.setFolderColor(folder, in: space.id, color: color)
        let group = try XCTUnwrap(browser.extensionTabGroups.groups(in: space.id).first)
        XCTAssertEqual(group.color, .blue)
        XCTAssertEqual(browser.session.spaces[0].folders.first?.color, color)
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
