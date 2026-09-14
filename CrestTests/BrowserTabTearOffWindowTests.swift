import AppKit
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserTabTearOffWindowTests: XCTestCase {
    func testNativeDragOutsideOnlyWindowWaitsForBlankWindowThenMovesTab() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let row = try XCTUnwrap(fixture.root.sidebarInteraction.sidebarReorderState.frame(ofRow: .tab(fixture.tabID)))
        fixture.drag(from: row)
        // Drag decorations are separate native windows but cannot accept a drop.
        let sourceWindow = try XCTUnwrap(fixture.source.window)
        let point = sourceWindow.convertPoint(
            toScreen: CGPoint(
                x: fixture.outside.x, y: (sourceWindow.contentView?.bounds.height ?? 0) - fixture.outside.y))
        let preview = NSPanel(
            contentRect: CGRect(x: point.x - 40, y: point.y - 40, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false
        preview.ignoresMouseEvents = true
        preview.orderFront(nil)
        defer { preview.close() }
        fixture.input.send(.leftMouseUp, at: fixture.outside)
        fixture.pump()

        let request = try XCTUnwrap(fixture.request)
        XCTAssertEqual(request.kind, .temporary)
        XCTAssertEqual(fixture.source.browser.selectedTab?.id, fixture.tabID)
        let destination = try XCTUnwrap(fixture.coordinator.existingModel(for: request.id))
        XCTAssertTrue(destination.browser.selectedSpace?.tabs.isEmpty == true)
        fixture.coordinator.attach(fixture.destinationWindow, to: request.id)

        XCTAssertEqual(destination.browser.selectedTab?.id, fixture.tabID)
        XCTAssertTrue(fixture.source.browser.selectedSpace?.tabs.isEmpty == true)
        XCTAssertNotNil(fixture.coordinator.existingModel(for: fixture.source.id))
        XCTAssertTrue(fixture.source.window?.isVisible == true)
    }

    func testEscapeCancelsSingleTabTearOffUntilMouseRelease() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let row = try XCTUnwrap(fixture.root.sidebarInteraction.sidebarReorderState.frame(ofRow: .tab(fixture.tabID)))
        fixture.drag(from: row)
        XCTAssertTrue(fixture.root.sidebarInteraction.sidebarReorderState.hasLiftInFlight)
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fixture.source.window!.windowNumber, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        fixture.input.send(.leftMouseDragged, at: CGPoint(x: fixture.outside.x + 5, y: fixture.outside.y))
        fixture.input.send(.leftMouseUp, at: fixture.outside)
        fixture.pump()

        XCTAssertNil(fixture.request)
        XCTAssertEqual(fixture.source.browser.selectedTab?.id, fixture.tabID)
        XCTAssertFalse(fixture.root.sidebarInteraction.sidebarReorderState.hasLiftInFlight)
    }

    @MainActor
    private final class Fixture {
        let coordinator: BrowserMacWindowCoordinator
        let source: BrowserMacWindowModel
        let root: BrowserRootModel
        let input: BrowserNativeMouseInput
        let tabID: TabID
        let destinationWindow: NSWindow
        let outside = CGPoint(x: 1_320, y: -120)
        var request: BrowserMacWindowRequest?

        init() throws {
            let tab = BrowserTab(title: "Tear off", url: URL(string: "about:blank"), placement: .current)
            tabID = tab.id
            let space = BrowserSpace(
                id: SpaceID(), profile: BrowsingProfile(), name: "Temporary windows", symbol: "globe",
                accent: .indigo, folders: [], tabs: [tab], selectedTabID: tab.id)
            let browser = BrowserStore(
                session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
                persistence: InMemoryBrowserSessionPersistence())
            let access = BrowserSpaceAccessController()
            coordinator = BrowserMacWindowCoordinator(
                browser: browser,
                pages: BrowserPagePool(monitorsMemoryPressure: false, usesEphemeralWebsiteDataStores: true),
                spaceAccess: access, windowStatePersistence: InMemoryBrowserWindowStatePersistence())
            source = try XCTUnwrap(coordinator.model(for: .initial))
            root = BrowserRootModel(
                browser: source.browser, pages: source.pages, chrome: source.chrome, spaceAccess: access,
                windowState: source.windowState, startupBehavior: .lastActiveTab,
                persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth)
            let window = NSWindow(
                contentRect: CGRect(x: 80, y: 80, width: 1_160, height: 620),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            destinationWindow = NSWindow(
                contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            destinationWindow.isReleasedWhenClosed = false
            input = BrowserNativeMouseInput(window: window)
            window.contentView = NSHostingView(
                rootView:
                    TearOffTestSurface(model: root)
                    .environment(root.sidebarInteraction)
                    .environment(
                        \.browserSidebarWindowDrop,
                        BrowserSidebarWindowDrop { [weak self, weak window] item in
                            guard let self, let window, let event = NSApp.currentEvent else { return false }
                            return BrowserMacWindowDropAction(
                                coordinator: self.coordinator, sourceWindowID: self.source.id,
                                open: { [weak self] in self?.request = $0 }
                            ).perform(item, at: window.convertPoint(toScreen: event.locationInWindow))
                        }))
            coordinator.attach(window, to: source.id)
            window.makeKeyAndOrderFront(nil)
            pump()
        }

        func drag(from row: CGRect) {
            let start = CGPoint(x: row.midX, y: row.midY)
            input.send(.leftMouseDown, at: start)
            for step in 1...16 {
                let fraction = CGFloat(step) / 16
                input.send(
                    .leftMouseDragged,
                    at: CGPoint(
                        x: start.x + (outside.x - start.x) * fraction,
                        y: start.y + (outside.y - start.y) * fraction))
            }
        }

        func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }

        func close() {
            input.close()
            coordinator.closeWindow(source.id)
            if let request { coordinator.closeWindow(request.id) }
            destinationWindow.close()
        }
    }
}

private struct TearOffTestSurface: View {
    let model: BrowserRootModel
    @Namespace private var commandNamespace
    @Namespace private var tabNamespace
    @State private var sidebarWidth = Double(BrowserChromeLayout.sidebarIdealWidth)

    var body: some View {
        BrowserRootShell(
            model: model, transientBrowsing: BrowserTransientBrowsingCoordinator(),
            spaceSettingsPresentation: BrowserSpaceSettingsPresentationState(), shortcuts: nil,
            storedSidebarWidth: $sidebarWidth,
            windowTransparencyIsEnabled: false, windowTransparencyStrength: 0.5,
            commandSurfaceNamespace: commandNamespace, tabPromotionNamespace: tabNamespace)
    }
}
