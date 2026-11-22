import Foundation
import XCTest

@testable import Crest

/// "Fancy Move": when a ⇧⌘-held press picks a Split View card up, which slot
/// the gap it leaves is standing in, and how the row is drawn around it.
///
/// The gesture itself is a local `NSEvent` monitor no test can drive, which is
/// exactly why every decision it makes is a pure function. These are the
/// contract for those decisions.
final class BrowserSplitCardLiftTests: XCTestCase {

    // MARK: - Pickup

    /// Everything the ⇧⌘ pair is not. Plain ⌘-click still opens a link in a new
    /// tab, ⌥-click still downloads, ⌃-click is still a right-click, and adding
    /// a third modifier to ⇧⌘ hands the press back to the page rather than
    /// widening the carry's claim.
    func testEveryOtherModifierCombinationIsLeftToThePage() {
        XCTAssertFalse(Self.picksUp(modifiers: .command))
        XCTAssertFalse(Self.picksUp(modifiers: .shift))
        XCTAssertFalse(Self.picksUp(modifiers: .option))
        XCTAssertFalse(Self.picksUp(modifiers: .control))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .control]))
    }

    // MARK: - Fixtures

    private static func picksUp(
        modifiers: BrowserKeyboardModifierFlags = [.command, .shift],
        isInsideCard: Bool = true,
        isOverDivider: Bool = false,
        memberCount: Int = 2,
        isDraggingSidebarItem: Bool = false,
        isCommandPalettePresented: Bool = false
    ) -> Bool {
        BrowserSplitCardLift.picksUp(
            modifiers: modifiers,
            isInsideCard: isInsideCard,
            isOverDivider: isOverDivider,
            memberCount: memberCount,
            isDraggingSidebarItem: isDraggingSidebarItem,
            isCommandPalettePresented: isCommandPalettePresented
        )
    }
}
