import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteModelActivationTests: XCTestCase {
    func testActivationCarriesExactAssignmentsAndRejectsAStaleSource() throws {
        let sourceTab = BrowserTab.startPage(
            id: TabID(rawValue: uuid(0x11)),
            lastActivatedAt: fixedDate
        )
        let targetTab = BrowserTab(
            id: TabID(rawValue: uuid(0x12)),
            title: "Target",
            url: URL(fileURLWithPath: "/palette-target"),
            placement: .current,
            lastActivatedAt: fixedDate
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: uuid(0x21)),
            profile: BrowsingProfile(id: uuid(0x31)),
            name: "Palette",
            symbol: "command",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab, targetTab],
            selectedTabID: sourceTab.id
        )
        var sourceIsAvailable = false
        var capturedSource: BrowserTabRuntimeAssignment?
        var capturedTarget: BrowserTabRuntimeAssignment?
        var dismissalCount = 0
        let model = BrowserCommandPaletteModel(
            space: space,
            selectedTabID: sourceTab.id,
            initialQuery: "",
            otherSpaces: [],
            commands: nil,
            isSourceAvailable: { _ in sourceIsAvailable },
            selectTab: { source, target in
                capturedSource = source
                capturedTarget = target
                return true
            },
            selectTabInSpace: nil,
            openURL: { _, _ in false },
            dismiss: { dismissalCount += 1 }
        )
        let targetResult = try XCTUnwrap(
            model.results.first { $0.faviconTabID == targetTab.id }
        )

        model.activate(targetResult)
        XCTAssertNil(capturedSource)
        XCTAssertNil(capturedTarget)
        XCTAssertEqual(dismissalCount, 0)

        sourceIsAvailable = true
        model.activate(targetResult)

        XCTAssertEqual(
            capturedSource,
            BrowserTabRuntimeAssignment(
                tabID: sourceTab.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
        XCTAssertEqual(
            capturedTarget,
            BrowserTabRuntimeAssignment(
                tabID: targetTab.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
        XCTAssertEqual(dismissalCount, 1)
    }

    private var fixedDate: Date {
        Date(timeIntervalSinceReferenceDate: 600)
    }

    private func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x4D, 0x4F, 0x44, finalByte
            ))
    }
}
