import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionTabGroupStoreTests: XCTestCase {
    private let claude = BrowserExtensionServiceClientID("claude")!
    private let chatgpt = BrowserExtensionServiceClientID("chatgpt")!

    func testGroupsAreBrowserWideSoASecondExtensionSeesAndUpdatesTheFirstsGroup() throws {
        let store = BrowserExtensionTabGroupStore()
        let space = SpaceID()
        let tab = TabID()
        store.register(client: claude, spaceID: space)
        store.register(client: chatgpt, spaceID: space)

        let created = try store.group([tab], in: space, into: nil)
        XCTAssertEqual(store.groups(in: space).map(\.id), [created.id])
        let updated = try store.update(
            created.id, in: space, title: "Research", color: .orange, isCollapsed: nil)
        XCTAssertEqual(updated.title, "Research")
        XCTAssertEqual(updated.color, .orange)
        XCTAssertEqual(store.membership(in: space), [tab: created.id])
        XCTAssertEqual(store.space(for: chatgpt), space)
    }

    func testAnotherSpacesRegistryIsUnreachable() throws {
        let store = BrowserExtensionTabGroupStore()
        let work = SpaceID()
        let personal = SpaceID()
        let group = try store.group([TabID()], in: work, into: nil)

        XCTAssertThrowsError(try store.group(group.id, in: personal))
        XCTAssertTrue(store.groups(in: personal).isEmpty)
        XCTAssertTrue(store.membership(in: personal).isEmpty)
    }

    func testEventsFanOutToEverySharedSpaceClientAndNeverAcrossSpaces() async throws {
        let store = BrowserExtensionTabGroupStore()
        let space = SpaceID()
        let otherSpace = SpaceID()
        let outsider = BrowserExtensionServiceClientID("outsider")!
        store.register(client: claude, spaceID: space)
        store.register(client: chatgpt, spaceID: space)
        store.register(client: outsider, spaceID: otherSpace)
        var claudeEvents = store.events(for: claude).makeAsyncIterator()
        var chatgptEvents = store.events(for: chatgpt).makeAsyncIterator()
        var outsiderEvents = store.events(for: outsider).makeAsyncIterator()

        let group = try store.group([TabID()], in: space, into: nil)
        let createdForClaude = await claudeEvents.next()
        let createdForChatGPT = await chatgptEvents.next()
        XCTAssertEqual(createdForClaude?.kind, .created)
        XCTAssertEqual(createdForClaude?.group.id, group.id)
        XCTAssertEqual(createdForChatGPT?.kind, .created)

        _ = try store.update(group.id, in: space, title: "Docs", color: nil, isCollapsed: nil)
        let updatedEvent = await claudeEvents.next()
        XCTAssertEqual(updatedEvent?.kind, .updated)

        // The outsider watches a different Space and must have heard nothing;
        // proven by giving it its own event and seeing that one arrive first.
        let unrelated = try store.group([TabID()], in: otherSpace, into: nil)
        let outsiderEvent = await outsiderEvents.next()
        XCTAssertEqual(outsiderEvent?.kind, .created)
        XCTAssertEqual(outsiderEvent?.group.id, unrelated.id)
    }

    func testMembershipChangesDoNotMasqueradeAsChromesVisualUpdate() async throws {
        let store = BrowserExtensionTabGroupStore()
        let space = SpaceID()
        let first = TabID()
        let second = TabID()
        store.register(client: claude, spaceID: space)
        let group = try store.group([first], in: space, into: nil)
        var events = store.events(for: claude).makeAsyncIterator()

        // Chrome reports a tab joining a group through the tabs events, not
        // `tabGroups.onUpdated`, so adding one must publish nothing. The
        // colour change afterwards is what proves the queue was empty.
        _ = try store.group([second], in: space, into: group.id)
        _ = try store.update(group.id, in: space, title: nil, color: .cyan, isCollapsed: nil)
        let event = await events.next()
        XCTAssertEqual(event?.kind, .updated)
        XCTAssertEqual(event?.group.color, .cyan)
    }

    func testEmptyingAGroupRemovesItAndSaysSoOnce() async throws {
        let store = BrowserExtensionTabGroupStore()
        let space = SpaceID()
        let tab = TabID()
        store.register(client: claude, spaceID: space)
        var events = store.events(for: claude).makeAsyncIterator()
        let group = try store.group([tab], in: space, into: nil)
        let created = await events.next()
        XCTAssertEqual(created?.kind, .created)

        store.ungroup([tab], in: space)
        let removed = await events.next()
        XCTAssertEqual(removed?.kind, .removed)
        XCTAssertEqual(removed?.group.id, group.id)
        XCTAssertTrue(store.groups(in: space).isEmpty)

        // A second ungroup changes nothing and must not re-announce.
        store.ungroup([tab], in: space)
        let next = try store.group([TabID()], in: space, into: nil)
        let recreated = await events.next()
        XCTAssertEqual(recreated?.group.id, next.id)
    }

    func testRepairDropsClosedTabsAndWholeSpacesThatDisappeared() async throws {
        let store = BrowserExtensionTabGroupStore()
        let closing = BrowserTab(title: "Closing", url: nil, placement: .current)
        let staying = BrowserTab(title: "Staying", url: nil, placement: .current)
        var space = BrowserSession.makeBlankSpace(number: 1)
        space.tabs = [closing, staying]
        store.register(client: claude, spaceID: space.id)
        var events = store.events(for: claude).makeAsyncIterator()
        let emptied = try store.group([closing.id], in: space.id, into: nil)
        let survivor = try store.group([staying.id], in: space.id, into: nil)
        _ = await events.next()
        _ = await events.next()

        var reduced = space
        reduced.tabs = [staying]
        store.repair(using: BrowserSession(spaces: [reduced], selectedSpaceID: reduced.id))

        let removed = await events.next()
        XCTAssertEqual(removed?.kind, .removed)
        XCTAssertEqual(removed?.group.id, emptied.id)
        XCTAssertEqual(store.groups(in: space.id).map(\.id), [survivor.id])

        // A Space that vanished takes its registry and its clients with it.
        let elsewhere = BrowserSession.makeBlankSpace(number: 2)
        store.repair(using: BrowserSession(spaces: [elsewhere], selectedSpaceID: elsewhere.id))
        XCTAssertTrue(store.groups(in: space.id).isEmpty)
        XCTAssertNil(store.space(for: claude))
    }

    func testUnregisteringAClientEndsItsStreamWithoutTouchingTheRegistry() async throws {
        let store = BrowserExtensionTabGroupStore()
        let space = SpaceID()
        store.register(client: claude, spaceID: space)
        store.register(client: chatgpt, spaceID: space)
        let group = try store.group([TabID()], in: space, into: nil)
        var events = store.events(for: claude).makeAsyncIterator()

        store.unregister(client: claude)
        let finished = await events.next()
        XCTAssertNil(finished)
        XCTAssertNil(store.space(for: claude))
        XCTAssertEqual(store.groups(in: space).map(\.id), [group.id])
        XCTAssertEqual(store.space(for: chatgpt), space)
    }
}
