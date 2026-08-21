import SwiftUI
import XCTest

@testable import CrestMobile

/// The iPad menu bar used to spell every chord out as a literal. The bindings
/// now resolve through `BrowserShortcutStore`, so this pins each shared default
/// to the literal the matching menu item carried before the move: a hardware
/// keyboard that never touched the rebinding surface must behave identically.
@MainActor
final class MobileBrowserShortcutDefaultsTests: XCTestCase {
    func testEveryMobileBindingKeepsItsPreviousLiteralDefault() {
        let store = BrowserShortcutStore.inMemory()
        for expectation in previousLiterals {
            XCTAssertEqual(
                store.keyboardShortcut(for: expectation.command),
                expectation.shortcut,
                "\(expectation.command.rawValue) resolves to a different chord than the literal it replaced."
            )
        }
    }

    func testNumberedTabAndSpaceSelectionKeepTheirPreviousLiterals() {
        let store = BrowserShortcutStore.inMemory()
        for number in 1...9 {
            let digit = KeyEquivalent(Character(String(number)))
            XCTAssertEqual(
                BrowserShortcutCommand.tabSelection(number).flatMap {
                    store.keyboardShortcut(for: $0)
                },
                KeyboardShortcut(digit, modifiers: .command),
                "Select Tab \(number) resolves to a different chord than ⌘\(number)."
            )
            XCTAssertEqual(
                BrowserShortcutCommand.spaceSelection(number).flatMap {
                    store.keyboardShortcut(for: $0)
                },
                KeyboardShortcut(digit, modifiers: .control),
                "Select Space \(number) resolves to a different chord than ⌃\(number)."
            )
        }
    }

    /// The arrow and bracket duplicates stay literal because the store holds one
    /// binding per command. They only stay safe while no shared default claims
    /// the same chord, which is what this pins.
    func testMobileOnlyAliasChordsAreUnclaimedByTheSharedTable() {
        let store = BrowserShortcutStore.inMemory()
        let aliases = [
            BrowserShortcut(key: .special(.leftArrow), modifiers: [.command]),
            BrowserShortcut(key: .special(.rightArrow), modifiers: [.command]),
            BrowserShortcut(key: .character("["), modifiers: [.command, .shift]),
            BrowserShortcut(key: .character("]"), modifiers: [.command, .shift]),
        ]
        for alias in aliases {
            XCTAssertEqual(
                store.commands(assignedTo: alias).map(\.rawValue),
                [],
                "A rebindable command now defaults to a chord the iPad menu also spells out literally."
            )
        }
    }

    private var previousLiterals: [(command: BrowserShortcutCommand, shortcut: KeyboardShortcut?)] {
        [
            (.newWindow, KeyboardShortcut("n", modifiers: .command)),
            (.newTab, KeyboardShortcut("t", modifiers: .command)),
            (.newPrivateWindow, KeyboardShortcut("n", modifiers: [.command, .shift])),
            (.closeTabOrWindow, KeyboardShortcut("w", modifiers: .command)),
            (.openLocation, KeyboardShortcut("l", modifiers: .command)),
            (.back, KeyboardShortcut("[", modifiers: .command)),
            (.forward, KeyboardShortcut("]", modifiers: .command)),
            (.reloadPage, KeyboardShortcut("r", modifiers: .command)),
            (.stopLoading, KeyboardShortcut(".", modifiers: .command)),
            (.reloadFromOrigin, KeyboardShortcut("r", modifiers: [.command, .shift])),
            (.toggleSelectedTabPinned, KeyboardShortcut("d", modifiers: .command)),
            (.duplicateTab, nil),
            (.reopenClosedTab, KeyboardShortcut("t", modifiers: [.command, .shift])),
            (.clearUnpinnedTabs, KeyboardShortcut("k", modifiers: [.command, .shift])),
            (.archiveTab, KeyboardShortcut("e", modifiers: .command)),
            (.previousTab, KeyboardShortcut(.upArrow, modifiers: [.command, .option])),
            (.nextTab, KeyboardShortcut(.downArrow, modifiers: [.command, .option])),
            (.mostRecentTab, KeyboardShortcut(KeyEquivalent("\t"), modifiers: .control)),
            (.splitWithNextTab, nil),
            (.focusNextSplitCard, KeyboardShortcut(.rightArrow, modifiers: [.control, .command])),
            (.focusPreviousSplitCard, KeyboardShortcut(.leftArrow, modifiers: [.control, .command])),
            (.moveSplitCardLeft, KeyboardShortcut(.leftArrow, modifiers: [.command, .shift])),
            (.moveSplitCardRight, KeyboardShortcut(.rightArrow, modifiers: [.command, .shift])),
            (.removeTabFromSplit, nil),
            (.separateSplitTabs, KeyboardShortcut("u", modifiers: [.command, .option])),
            (.previousSpace, KeyboardShortcut(.leftArrow, modifiers: [.command, .option])),
            (.nextSpace, KeyboardShortcut(.rightArrow, modifiers: [.command, .option])),
            (.toggleReaderMode, nil),
            (.toggleContentBlocking, nil),
            (.findInPage, KeyboardShortcut("f", modifiers: .command)),
            (.zoomIn, KeyboardShortcut("+", modifiers: .command)),
            (.zoomOut, KeyboardShortcut("-", modifiers: .command)),
            (.actualSize, KeyboardShortcut("0", modifiers: .command)),
            (.copyPageLink, KeyboardShortcut("c", modifiers: [.command, .shift])),
            (.copyPageLinkAsMarkdown, KeyboardShortcut("c", modifiers: [.command, .shift, .option])),
            (.printPage, KeyboardShortcut("p", modifiers: .command)),
            (.toggleSidebar, KeyboardShortcut("s", modifiers: .command)),
            (.showHistory, KeyboardShortcut("y", modifiers: .command)),
            (.showArchive, nil),
            (.showDownloads, KeyboardShortcut("j", modifiers: [.command, .shift])),
        ]
    }
}
