import XCTest

@testable import Crest

final class BrowserExtensionTabGroupRegistryTests: XCTestCase {
    func testGroupIDsAreSessionUniqueAndCannotCrossSpaces() throws {
        var registry = BrowserExtensionTabGroupRegistry()
        let work = SpaceID()
        let personal = SpaceID()
        let first = try registry.group([TabID()], in: work)
        let second = try registry.group([TabID()], in: personal)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertThrowsError(try registry.get(first.id, in: personal))
        XCTAssertEqual(registry.groups(in: work), [first])
        XCTAssertEqual(registry.groups(in: personal), [second])
    }

    func testMovingTheLastTabToAnotherGroupRemovesTheEmptyGroup() throws {
        var registry = BrowserExtensionTabGroupRegistry()
        let space = SpaceID()
        let firstTab = TabID()
        let secondTab = TabID()
        let first = try registry.group([firstTab], in: space)
        let second = try registry.group([secondTab], in: space)

        let merged = try registry.group([firstTab, firstTab], in: space, into: second.id)

        XCTAssertEqual(merged.tabs, [secondTab, firstTab])
        XCTAssertEqual(registry.groups(in: space), [merged])
        XCTAssertThrowsError(try registry.get(first.id, in: space))
        XCTAssertEqual(registry.groupID(for: firstTab, in: space), second.id)
    }

    func testPartialUpdatesPreserveUnspecifiedPropertiesAndMembership() throws {
        var registry = BrowserExtensionTabGroupRegistry()
        let space = SpaceID()
        let tab = TabID()
        let original = try registry.group([tab], in: space)
        XCTAssertEqual(original.color, .grey)
        XCTAssertFalse(original.isCollapsed)

        _ = try registry.update(original.id, in: space, title: "Claude", color: .orange, isCollapsed: true)
        let renamed = try registry.update(original.id, in: space, title: "Research")

        XCTAssertEqual(renamed.title, "Research")
        XCTAssertEqual(renamed.color, .orange)
        XCTAssertTrue(renamed.isCollapsed)
        XCTAssertEqual(renamed.tabs, [tab])
    }

    func testUngroupAndRepairRemoveEmptyGroupsWithoutAffectingAnotherSpace() throws {
        var registry = BrowserExtensionTabGroupRegistry()
        let space = SpaceID()
        let otherSpace = SpaceID()
        let first = TabID()
        let second = TabID()
        let group = try registry.group([first, second], in: space)
        let unrelated = try registry.group([TabID()], in: otherSpace)

        registry.ungroup([first], in: space)
        XCTAssertNil(registry.groupID(for: first, in: space))
        XCTAssertEqual(try registry.get(group.id, in: space).tabs, [second])
        registry.repair(in: space, liveTabs: [])

        XCTAssertTrue(registry.groups(in: space).isEmpty)
        XCTAssertEqual(registry.groups(in: otherSpace), [unrelated])
    }

    func testInvalidGroupingDoesNotPartiallyMoveTabs() throws {
        var registry = BrowserExtensionTabGroupRegistry()
        let space = SpaceID()
        let otherSpace = SpaceID()
        let tab = TabID()
        let original = try registry.group([tab], in: space)
        let foreign = try registry.group([TabID()], in: otherSpace)

        XCTAssertThrowsError(try registry.group([], in: space))
        XCTAssertThrowsError(try registry.group([tab], in: space, into: foreign.id))
        XCTAssertEqual(registry.groups(in: space), [original])
        XCTAssertEqual(registry.groups(in: otherSpace), [foreign])
    }
}
