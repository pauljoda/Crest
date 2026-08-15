import Foundation
import XCTest

@testable import Crest

/// The guard set behind pointer-driven Split View focus.
///
/// The tracking area and the event monitor that feed it are AppKit machinery no
/// test can drive, which is exactly why the decision they consult is a pure
/// function. These tests are the contract for when focus is allowed to move.
final class BrowserSplitFocusPolicyTests: XCTestCase {
    func testHoverFocusesAnUnfocusedCardWhenTheSettingIsOn() {
        XCTAssertTrue(
            BrowserSplitFocusPolicy.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
    }

    func testHoverDoesNothingWhileTheSettingIsOff() {
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnHover(
                followsMouse: false,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
    }

    /// Focus is selection, and the selection observer resigns address focus, so
    /// a pointer drifting across a card while someone types a URL would discard
    /// what they had typed.
    func testHoverNeverInterruptsAddressBarTyping() {
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: true,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
    }

    func testHoverStandsAsideForADragInFlightAndForTheCommandPalette() {
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: true,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: true
            )
        )
    }

    /// A carried card crosses every neighbour on its way to a new slot, and the
    /// card somebody is holding already took focus at the pickup. Focus arriving
    /// at each column it passes over would reselect the split several times per
    /// gesture.
    func testHoverStandsAsideForACardBeingCarried() {
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnHover(
                followsMouse: true,
                isCardFocused: false,
                isAddressEditing: false,
                isDraggingSidebarItem: false,
                isCarryingCard: true,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: false,
                isCarryingCard: true,
                isCommandPalettePresented: false
            )
        )
    }

    func testHoverOverTheFocusedCardChangesNothing() {
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnHover(
                followsMouse: true,
                isCardFocused: true,
                isAddressEditing: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
    }

    /// Click-to-focus is how Split View works rather than a behaviour to opt
    /// into, so the preference has no say in it — it is not even an input.
    func testClickFocusesAnUnfocusedCardRegardlessOfTheHoverSetting() {
        XCTAssertTrue(
            BrowserSplitFocusPolicy.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
    }

    /// A deliberate click into a card is a decision to leave the address field,
    /// which is why address editing is not a click guard the way it is a hover
    /// guard.
    func testClickIsRefusedOnlyByFocusADragOrThePalette() {
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnClick(
                isCardFocused: true,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: true,
                isCarryingCard: false,
                isCommandPalettePresented: false
            )
        )
        XCTAssertFalse(
            BrowserSplitFocusPolicy.focusesOnClick(
                isCardFocused: false,
                isDraggingSidebarItem: false,
                isCarryingCard: false,
                isCommandPalettePresented: true
            )
        )
    }
}

/// Where the Follow Mouse preference is kept, mirroring the window-transparency
/// store's contract: defaults, live persistence through the injected port, and an
/// isolated launch that never constructs the persistent adapter.
@MainActor
final class BrowserSplitFocusPreferenceTests: XCTestCase {
    func testUserDefaultsPersistenceDefaultsToOffAndRoundTrips() {
        let suiteName =
            "BrowserSplitFocusPreferenceTests.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserSplitFocusPreferencePersistence(
            defaults: defaults
        )

        XCTAssertEqual(persistence.load(), BrowserSplitFocusPreference())
        XCTAssertFalse(persistence.load().followsMouse)

        persistence.saveFollowsMouse(true)

        XCTAssertTrue(
            defaults.bool(
                forKey: UserDefaultsBrowserSplitFocusPreferencePersistence
                    .followsMouseKey
            )
        )
        XCTAssertTrue(persistence.load().followsMouse)
    }

    func testStorePersistsLiveChangesThroughItsInjectedPort() {
        let persistence = InMemoryBrowserSplitFocusPreferencePersistence()
        let store = BrowserSplitFocusPreferenceStore(persistence: persistence)

        XCTAssertFalse(store.followsMouse)
        store.followsMouse = true

        XCTAssertEqual(
            persistence.preference,
            BrowserSplitFocusPreference(followsMouse: true)
        )
    }

    func testIsolatedLaunchNeverConstructsPersistentPreferences() {
        var persistentFactoryWasCalled = false
        let store = BrowserSplitFocusPreferenceStore.launch(
            usesIsolatedLaunch: true,
            makePersistentPersistence: {
                persistentFactoryWasCalled = true
                return InMemoryBrowserSplitFocusPreferencePersistence()
            },
            makeIsolatedPersistence: {
                InMemoryBrowserSplitFocusPreferencePersistence(
                    preference: BrowserSplitFocusPreference(followsMouse: true)
                )
            }
        )

        XCTAssertFalse(persistentFactoryWasCalled)
        XCTAssertTrue(store.followsMouse)
    }
}

/// The registry that turns a mouse-down location into the card it landed in.
@MainActor
final class BrowserSplitCardFrameRegistryTests: XCTestCase {
    func testAPointResolvesToTheCardWhoseFrameContainsIt() {
        let registry = BrowserSplitCardFrameRegistry()
        let leading = TabID()
        let trailing = TabID()
        registry.register(
            CGRect(x: 0, y: 0, width: 400, height: 600),
            for: leading
        )
        registry.register(
            CGRect(x: 408, y: 0, width: 400, height: 600),
            for: trailing
        )

        XCTAssertEqual(registry.tabID(containing: CGPoint(x: 12, y: 40)), leading)
        XCTAssertEqual(
            registry.tabID(containing: CGPoint(x: 500, y: 40)),
            trailing
        )
        XCTAssertNil(
            registry.tabID(containing: CGPoint(x: 404, y: 40)),
            "The gap between cards belongs to the divider, not to either card."
        )
        XCTAssertNil(registry.tabID(containing: CGPoint(x: 900, y: 40)))
    }

    func testACardThatLeavesTheRowStopsClaimingItsOldFrame() {
        let registry = BrowserSplitCardFrameRegistry()
        let tabID = TabID()
        registry.register(CGRect(x: 0, y: 0, width: 400, height: 600), for: tabID)

        registry.removeFrame(for: tabID)

        XCTAssertNil(registry.frame(for: tabID))
        XCTAssertNil(registry.tabID(containing: CGPoint(x: 12, y: 40)))
    }
}
