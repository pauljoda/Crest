import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import Crest

/// Native sidebar input must resolve a page target and commit the same split.
/// Each case owns an in-memory session, ephemeral pages, and its window.
@MainActor
final class BrowserSplitDragToSplitWindowTests: XCTestCase {

    func testAPointerDragFromTheSidebarIntoThePageOpensAndCommitsASplit() throws {
        let fixture = try makeHostedWindow()
        defer { fixture.input.close() }
        let state = fixture.model.sidebarInteraction.sidebarReorderState

        let contentCard = try XCTUnwrap(state.orderedSplitCardFrames.first)
        XCTAssertEqual(
            state.orderedSplitCardFrames.count,
            1,
            "The lone tab on show has to register as the card a drop joins."
        )

        let rowFrame = try XCTUnwrap(
            state.frame(ofRow: .tab(fixture.joiner.id)),
            "The sidebar row for the tab about to be dragged never measured."
        )
        let start = CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        // Well inside the content area, past the card's midpoint, so the drop
        // resolves to the slot after the tab already on show.
        let overPage = CGPoint(x: contentCard.maxX - 60, y: contentCard.midY)

        fixture.send(.leftMouseDown, at: start)
        for step in 1...12 {
            let fraction = CGFloat(step) / 12
            fixture.send(
                .leftMouseDragged,
                at: CGPoint(
                    x: start.x + (overPage.x - start.x) * fraction,
                    y: start.y + (overPage.y - start.y) * fraction
                )
            )
        }

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 1),
            "A pointer past the presented card resolves the slot after it."
        )
        XCTAssertTrue(
            state.hasEnteredSplitContent,
            "Reaching the content area latches the columns layout for the drag."
        )
        XCTAssertEqual(
            state.liftTargetShape,
            .webpageCard,
            "The lift morphs toward what the drop would make of it."
        )
        XCTAssertEqual(
            state.liftPreview?.tabID,
            fixture.joiner.id,
            "The lift is drawn by the window host, not by the row."
        )

        let shrunkCard = try XCTUnwrap(state.orderedSplitCardFrames.first)
        XCTAssertLessThan(
            shrunkCard.width,
            contentCard.width,
            "The drop column has to open a real slot beside the presented card."
        )

        fixture.send(.leftMouseUp, at: overPage)
        let space = try XCTUnwrap(
            fixture.model.browser.session.space(id: fixture.assignment.spaceID)
        )
        let groupID = try XCTUnwrap(
            space.splitGroup(containing: fixture.joiner.id),
            "Releasing over the page has to commit the split."
        )
        XCTAssertEqual(
            space.splitGroupMembers(of: groupID).map(\.title),
            ["Presented", "Joiner"]
        )
        XCTAssertEqual(space.selectedTabID, fixture.joiner.id)
        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.liftPreview)
        pump(0.4)

        // The drop column is not a hint about where a card would go, it is that
        // card's own column drawn a moment early. The presented card therefore
        // holds the width and position it had mid-drag, and the joining card
        // lands in the placeholder's frame at the same width: half the row.
        let landed = state.orderedSplitCardFrames
        XCTAssertEqual(landed.count, 2)
        guard landed.count == 2 else { return }
        XCTAssertEqual(
            landed[0].minX,
            shrunkCard.minX,
            accuracy: 0.5,
            "The card already on show must not move when the drop commits."
        )
        XCTAssertEqual(landed[0].width, shrunkCard.width, accuracy: 0.5)
        XCTAssertEqual(
            landed[1].width,
            shrunkCard.width,
            accuracy: 0.5,
            "The joining card takes exactly the half the placeholder held."
        )
        XCTAssertEqual(
            landed[1].minX - landed[0].maxX,
            BrowserSplitLayoutMetrics.interCardGap
                + BrowserChromeLayout.pageBrandSeamWidth * 2,
            accuracy: 0.5,
            "The two columns are separated by one inter-card gap, no more."
        )

    }

    /// The other half of the same gesture: a tab that is already the card on show
    /// resolves nothing anywhere over the page, and nothing about the layout
    /// moves. A refusal that still opened a placeholder would be a promise the
    /// commit declines.
    func testDraggingThePresentedTabOntoItsOwnPageResolvesNothing() throws {
        let fixture = try makeHostedWindow()
        defer { fixture.input.close() }
        let state = fixture.model.sidebarInteraction.sidebarReorderState

        let contentCard = try XCTUnwrap(state.orderedSplitCardFrames.first)
        let rowFrame = try XCTUnwrap(
            state.frame(ofRow: .tab(fixture.presented.id))
        )
        let start = CGPoint(x: rowFrame.midX, y: rowFrame.midY)

        fixture.send(.leftMouseDown, at: start)
        for x in stride(
            from: contentCard.minX + 40,
            through: contentCard.maxX - 40,
            by: 200
        ) {
            fixture.send(
                .leftMouseDragged,
                at: CGPoint(x: x, y: contentCard.midY)
            )
            XCTAssertNil(
                state.resolvedTarget,
                "A tab already on show has nothing to join at x \(x)."
            )
        }
        XCTAssertFalse(state.hasEnteredSplitContent)
        XCTAssertEqual(
            state.orderedSplitCardFrames,
            [contentCard],
            "A refused drag must not move the cards it is refused by."
        )
        XCTAssertNotNil(
            state.liftPreview,
            "A refused lift is still over the page, and still has to be seen."
        )

        fixture.send(.leftMouseUp, at: CGPoint(x: contentCard.midX, y: 300))

        let space = try XCTUnwrap(
            fixture.model.browser.session.space(id: fixture.assignment.spaceID)
        )
        XCTAssertNil(space.splitGroup(containing: fixture.presented.id))
    }

    // MARK: - Fixture

    /// A window showing one tab, with a second tab in the sidebar to drag.
    @MainActor
    private struct HostedWindow {
        let input: BrowserNativeMouseInput
        let model: BrowserRootModel
        let assignment: BrowserSpaceRuntimeAssignment
        let presented: BrowserTab
        let joiner: BrowserTab

        func send(_ type: NSEvent.EventType, at global: CGPoint) {
            input.send(type, at: global)
        }
    }

    private func makeHostedWindow(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HostedWindow {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let presented = BrowserTab(
            id: TabID(rawValue: Self.uuid(0x01)),
            title: "Presented",
            url: URL(string: "about:blank"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: date
        )
        let joiner = BrowserTab(
            id: TabID(rawValue: Self.uuid(0x02)),
            title: "Joiner",
            url: URL(string: "about:blank"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: date
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x03)),
            profile: BrowsingProfile(id: Self.uuid(0x04)),
            name: "Drag To Split",
            symbol: "books.vertical.fill",
            accent: .indigo,
            branding: .initial(accent: .indigo, symbol: "books.vertical.fill"),
            folders: [],
            tabs: [presented, joiner],
            selectedTabID: presented.id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let model = BrowserRootModel(
            browser: browser,
            pages: BrowserPagePool(
                browsingMode: .privateBrowsing,
                usesEphemeralWebsiteDataStores: true
            ),
            chrome: BrowserChromeState(sidebarIsPresented: true),
            spaceAccess: BrowserSpaceAccessController(),
            windowState: nil,
            startupBehavior: .showStartPage,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )

        let host = NSHostingView(
            rootView: BrowserSplitDragToSplitTestSurface(model: model)
                .environment(model.sidebarInteraction)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 120, y: 120, width: 1_160, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // ARC owns this window; letting AppKit release it on close would
        // over-release it the moment the test's autorelease pool drains.
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        pump(0.6)

        return HostedWindow(
            input: BrowserNativeMouseInput(window: window),
            model: model,
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            presented: presented,
            joiner: joiner
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x44, 0x52, 0x41, 0x47, 0x54, 0x4F, 0x53, 0x50,
                0x4C, 0x49, 0x54, 0x57, 0x49, 0x4E, 0x44, finalByte
            )
        )
    }
}

/// Runs the main run loop long enough for SwiftUI to answer what just happened.
@MainActor
private func pump(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// The shell as the app composes it, with nothing standing in for it.
private struct BrowserSplitDragToSplitTestSurface: View {
    let model: BrowserRootModel

    @Namespace private var commandSurfaceNamespace
    @Namespace private var tabPromotionNamespace
    @State private var sidebarWidth = Double(
        BrowserChromeLayout.sidebarIdealWidth
    )

    var body: some View {
        BrowserRootShell(
            model: model,
            transientBrowsing: BrowserTransientBrowsingCoordinator(),
            spaceSettingsPresentation: BrowserSpaceSettingsPresentationState(),
            shortcuts: nil,
            storedSidebarWidth: $sidebarWidth,
            windowTransparencyIsEnabled: false,
            windowTransparencyStrength: 0.5,
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace
        )
    }
}
