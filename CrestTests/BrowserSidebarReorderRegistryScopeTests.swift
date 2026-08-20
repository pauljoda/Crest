import CoreGraphics
import Foundation
import XCTest

@testable import Crest

/// Which rows a sidebar drag is allowed to count.
///
/// One `BrowserSidebarReorderState` belongs to a `BrowserStore`, and a store is
/// what every window onto a session shares — macOS opens more than one — so
/// every sidebar on screen registers its rows into the same registry. A single
/// sidebar adds to it more than once as well: its Space pager keeps the pages
/// either side of the visible one alive so a swipe can already show them, and
/// each of those pages measures its own Space's rows. A section identity is only
/// a placement, so all of it arrives in one bucket.
///
/// The pinned grid is where that shows first, because it is the only run with a
/// cap. Counted across every sidebar on screen, a grid with room to spare
/// reaches the cap and refuses the pin it is being offered — and refuses it in
/// silence, since a refused target means no slot, no insertion line, and no
/// reason given. Ordering goes the same way: a Space alongside has tiles on the
/// same line, and the pointer reads them as already passed.
@MainActor
final class BrowserSidebarReorderRegistryScopeTests: XCTestCase {

    /// A drag counts and orders among its own Space's tiles, so a Space
    /// alongside can neither fill its grid nor push its insertion point along.
    ///
    /// Eleven foreign tiles and two of its own is past the cap, and four of the
    /// foreign ones sit on the pointer's own line, to its left. Counted
    /// together, the grid has no room at all, and the slot the pointer is over
    /// is the sixth rather than the second.
    func testAForeignSpacesPinnedRowsNeitherFillNorReorderThisDragsGrid() {
        let fixture = ReorderRegistryFixture(ownPinCount: 2)
        let state = fixture.browser.sidebarReorderState
        fixture.register(in: state)

        fixture.liftTheJoiner(in: state, to: CGPoint(x: 144, y: 92))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(
                section: .tabs(placement: .pinned, folderID: nil),
                beforeID: .tab(fixture.ownPins[1].id),
                index: 1
            ),
            "A grid holding two tiles has room, and the pointer is over its "
                + "second slot — whatever the Space alongside has pinned."
        )
        XCTAssertEqual(
            state.liftTargetShape,
            .pinnedTile,
            "A resolved pinned slot morphs the lift into the tile it will be."
        )
        XCTAssertNil(
            state.indicator(for: .tab(fixture.foreignPins[0].id)),
            "A row this drag cannot land beside must not draw its seam."
        )
        XCTAssertEqual(
            state.displacement(for: .tab(fixture.foreignPins[0].id)),
            .zero,
            "Nor step aside for it."
        )
    }

    /// The cap still bites where it is meant to. Scoping the count must not
    /// become a way of ignoring it: a grid already full of this Space's own tabs
    /// has nowhere to put another, so the drag resolves nothing rather than
    /// opening a slot the release would decline.
    func testAGridFullOfItsOwnTabsStillRefusesAnIncomingPin() {
        let fixture = ReorderRegistryFixture(
            ownPinCount: BrowserSpace.maximumPinnedTabs
        )
        let state = fixture.browser.sidebarReorderState
        fixture.register(in: state)

        fixture.liftTheJoiner(in: state, to: CGPoint(x: 144, y: 92))

        XCTAssertNil(
            state.resolvedTarget,
            "A grid at the cap has to refuse the drop instead of promising a "
                + "slot the commit would decline."
        )
        XCTAssertEqual(
            state.liftTargetShape,
            .row,
            "Nothing resolved, so the lift holds the row shape it started as."
        )
    }
}

// MARK: - Fixture

private let pinnedSection = BrowserSidebarReorderSection.tabs(
    placement: .pinned,
    folderID: nil
)
private let currentSection = BrowserSidebarReorderSection.tabs(
    placement: .current,
    folderID: nil
)

/// Where a 390-point sidebar puts the runs this drag moves between. The pinned
/// zone is three tile lines deep, which is what a grid at the cap measures.
private let pinnedZone = CGRect(x: 8, y: 60, width: 374, height: 192)
private let currentZone = CGRect(x: 8, y: 240, width: 374, height: 300)
private let joinerRow = CGRect(x: 8, y: 260, width: 374, height: 44)
private let pageWidth: CGFloat = 390
private let tileSize = CGSize(width: 88, height: 64)
private let tileStride = CGSize(width: 92, height: 64)
private let gridColumns = 4

/// Reading-order cell geometry for a grid on the page `pageOffset` away.
private func tile(_ index: Int, pageOffset: CGFloat) -> CGRect {
    CGRect(
        x: pinnedZone.minX
            + pageOffset
            + CGFloat(index % gridColumns) * tileStride.width,
        y: pinnedZone.minY + CGFloat(index / gridColumns) * tileStride.height,
        width: tileSize.width,
        height: tileSize.height
    )
}

/// A two-Space session, the way one store holds every Space every window shows:
/// the Space the drag happens in, and one alongside whose sidebar — a second
/// window, or the pager page next door — has a nearly full grid of its own.
@MainActor
private struct ReorderRegistryFixture {
    let browser: BrowserStore
    let ownPins: [BrowserTab]
    let foreignPins: [BrowserTab]
    let joiner: BrowserTab

    private let ownSpaceID = SpaceID(rawValue: uuid(0x01))
    private let ownProfileID = uuid(0x02)
    private let foreignSpaceID = SpaceID(rawValue: uuid(0x03))
    private let foreignProfileID = uuid(0x04)

    init(ownPinCount: Int) {
        ownPins = (0..<ownPinCount).map { index in
            makeTab(
                id: TabID(rawValue: uuid(UInt8(0x10 + index))),
                title: "Own Pin \(index)",
                placement: .pinned
            )
        }
        // One short of the cap, so nothing here is a grid that is genuinely
        // full — only the sum of two grids is.
        foreignPins = (0..<(BrowserSpace.maximumPinnedTabs - 1)).map { index in
            makeTab(
                id: TabID(rawValue: uuid(UInt8(0x50 + index))),
                title: "Foreign Pin \(index)",
                placement: .pinned
            )
        }
        joiner = makeTab(
            id: TabID(rawValue: uuid(0x40)),
            title: "Joiner",
            placement: .current
        )
        let own = makeSpace(
            id: ownSpaceID,
            profileID: ownProfileID,
            name: "Dragging",
            tabs: ownPins + [joiner]
        )
        let foreign = makeSpace(
            id: foreignSpaceID,
            profileID: foreignProfileID,
            name: "Alongside",
            tabs: foreignPins
        )
        browser = BrowserStore(
            session: BrowserSession(
                spaces: [own, foreign],
                selectedSpaceID: own.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
    }

    var ownSpace: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: ownSpaceID,
            profileID: ownProfileID
        )
    }

    var foreignSpace: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: foreignSpaceID,
            profileID: foreignProfileID
        )
    }

    /// Registers what two sidebars on screen would: this Space's grid and
    /// current list where the pointer can reach them, and the Space alongside
    /// one page to the left, where it cannot.
    func register(in state: BrowserSidebarReorderState) {
        for (index, tab) in ownPins.enumerated() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id),
                    space: ownSpace,
                    section: pinnedSection,
                    frame: tile(index, pageOffset: 0)
                ),
                owner: UUID()
            )
        }
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(joiner.id),
                space: ownSpace,
                section: currentSection,
                frame: joinerRow
            ),
            owner: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(pinnedSection),
                frame: pinnedZone
            ),
            for: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(currentSection),
                frame: currentZone
            ),
            for: UUID()
        )

        for (index, tab) in foreignPins.enumerated() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id),
                    space: foreignSpace,
                    section: pinnedSection,
                    frame: tile(index, pageOffset: -pageWidth)
                ),
                owner: UUID()
            )
        }
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(pinnedSection),
                frame: pinnedZone.offsetBy(dx: -pageWidth, dy: 0)
            ),
            for: UUID()
        )
    }

    /// Lifts the current tab out of its row and holds the pointer at `pointer`.
    func liftTheJoiner(
        in state: BrowserSidebarReorderState,
        to pointer: CGPoint
    ) {
        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: joiner.id,
                    spaceID: ownSpaceID,
                    profileID: ownProfileID
                )
            ),
            section: currentSection,
            at: CGPoint(x: joinerRow.midX, y: joinerRow.midY)
        )
        state.update(pointer: pointer)
    }
}

private func makeSpace(
    id: SpaceID,
    profileID: UUID,
    name: String,
    tabs: [BrowserTab]
) -> BrowserSpace {
    BrowserSpace(
        id: id,
        profile: BrowsingProfile(id: profileID),
        name: name,
        symbol: "rectangle.stack",
        accent: .indigo,
        folders: [],
        tabs: tabs,
        selectedTabID: tabs.first?.id
    )
}

private func makeTab(
    id: TabID,
    title: String,
    placement: TabPlacement
) -> BrowserTab {
    BrowserTab(
        id: id,
        title: title,
        url: URL(fileURLWithPath: "/crest-reorder-registry-scope/\(title)"),
        placement: placement,
        lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func uuid(_ finalByte: UInt8) -> UUID {
    UUID(
        uuid: (
            0x52, 0x45, 0x47, 0x49, 0x53, 0x54, 0x52, 0x59,
            0x53, 0x43, 0x4F, 0x50, 0x45, 0x00, 0x00, finalByte
        )
    )
}
