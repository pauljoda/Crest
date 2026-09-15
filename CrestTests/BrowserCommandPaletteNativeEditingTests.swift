import AppKit
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteNativeEditingTests: XCTestCase {
    func testArrowNavigationScrollsResultsAndWrapsWhileKeepingTheEditorFocused() async throws {
        let tabs = (0..<8).map {
            BrowserTab(title: "Result \($0)", url: URL(string: "https://example.invalid/\($0)"), placement: .current)
        }
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Results", symbol: "globe",
            accent: .indigo, folders: [], tabs: tabs, selectedTabID: tabs[0].id)
        let model = BrowserCommandPaletteModel(
            space: space, selectedTabID: tabs[0].id, initialQuery: "Result", commands: nil,
            isSourceAvailable: { _ in true }, selectTab: { _, _ in false },
            openURL: { _, _ in false }, dismiss: {})
        let fieldView = BrowserPlatformCommandPaletteField(
            model: model, presentation: .overlay, identifier: "command-palette-field", focused: false)
        let coordinator = fieldView.makeCoordinator()
        let field = fieldView.makeField(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        field.frame = NSRect(x: 0, y: 250, width: 600, height: 40)
        let host = NSHostingView(rootView: BrowserCommandPaletteResultList(model: model, maximumResultAreaHeight: 180))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 180)
        window.contentView?.addSubview(host)
        window.contentView?.addSubview(field)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        window.makeFirstResponder(field)
        field.selectText(nil)
        try await Task.sleep(for: .milliseconds(100))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let scroll = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        let initialOffset = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(model.results.count, 5)

        for _ in 1..<model.results.count {
            XCTAssertTrue(
                coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertEqual(model.selectedResultIndex, model.results.count - 1)
        XCTAssertGreaterThan(
            scroll.contentView.bounds.minY, initialOffset, "Arrow selection must reveal results below the viewport")
        XCTAssertTrue(field.currentEditor() === editor)
        let bottomOffset = scroll.contentView.bounds.minY

        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selectedResultIndex, 0)
        XCTAssertLessThan(
            scroll.contentView.bounds.minY, bottomOffset, "Wrapping must bring the first result back into view")

        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selectedResultIndex, model.results.count - 1)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, initialOffset)
        XCTAssertTrue(field.currentEditor() === editor)

        let keyboardOffset = scroll.contentView.bounds.minY
        model.selectResult(at: model.results.count - 2)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(
            scroll.contentView.bounds.minY, keyboardOffset, accuracy: 1,
            "Hover must not move the list under the pointer")

        model.query = "Result 0"
        await model.waitForPendingResults()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selectedResultIndex, 0)
        XCTAssertLessThan(scroll.contentView.bounds.minY, keyboardOffset, "A new query must reveal its first result")
    }

    func testEmptySpaceLauncherAcceptsNativeInputBeforeAndAfterClosingLastTab() async throws {
        let empty = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Empty", symbol: "globe",
            accent: .indigo, folders: [], tabs: [], selectedTabID: nil)
        let other = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Other", symbol: "globe",
            accent: .indigo, folders: [], tabs: [BrowserTab.startPage()], selectedTabID: nil)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [empty, other], selectedSpaceID: empty.id),
            persistence: InMemoryBrowserSessionPersistence(), browsingMode: .privateBrowsing)
        let pages = BrowserPagePool()
        let chrome = BrowserChromeState()
        let root = BrowserRootModel(
            browser: browser, pages: pages, chrome: chrome,
            spaceAccess: BrowserSpaceAccessController(), windowState: nil,
            startupBehavior: .lastActiveTab,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth)
        let host = NSHostingView(rootView: EmptySpacePaletteHost(model: root))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        for useLocation in [false, true] {
            XCTAssertNil(browser.selectedTab)
            if useLocation { chrome.openLocation() } else { root.openNewTab() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let field = try XCTUnwrap(
                descendants(of: host).compactMap { $0 as? NSTextField }.first {
                    $0.accessibilityIdentifier() == "command-palette-field"
                }, "An empty Space must expose the launcher without a source tab")
            XCTAssertTrue(browser.selectedSpace?.tabs.isEmpty == true)
            let coordinator = try XCTUnwrap(field.delegate as? BrowserPlatformCommandPaletteField.Coordinator)
            coordinator.model.dismiss()
            XCTAssertNil(chrome.commandPaletteMode)
            XCTAssertTrue(browser.selectedSpace?.tabs.isEmpty == true, "Cancel must not create a draft tab")

            if useLocation { chrome.openLocation() } else { root.openNewTab() }
            host.layoutSubtreeIfNeeded()
            window.makeFirstResponder(field)
            field.selectText(nil)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText(
                "https://empty-space.invalid/",
                replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            coordinator.editingChanged()
            await coordinator.model.waitForPendingResults()
            XCTAssertTrue(
                coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))

            let tab = try XCTUnwrap(browser.selectedTab)
            XCTAssertEqual(tab.url?.absoluteString, "https://empty-space.invalid/")
            XCTAssertEqual(browser.selectedSpace?.id, empty.id)
            XCTAssertEqual(browser.selectedSpace?.tabs.count, 1)
            XCTAssertEqual(pages.activeTabID, tab.id)
            XCTAssertEqual(root.address, "https://empty-space.invalid/")
            XCTAssertNil(chrome.commandPaletteMode)
            XCTAssertEqual(browser.session.space(id: other.id), other)
            browser.closeTab(tab.id)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func testRetainedStartPageCannotTakeFocusUntilEnabled() async throws {
        let fixture = makeEditor()
        let palette = BrowserCommandPalette(
            space: nil, selectedTabID: nil, isSourceAvailable: { _ in false },
            selectTab: { _, _ in false }, openURL: { _, _ in false }, dismiss: {}, presentation: .embedded)
        let host = NSHostingView(rootView: palette.environment(\.spaceContentIsInteractive, false))
        host.frame = CGRect(x: 420, y: 0, width: 400, height: 300)
        fixture.window.contentView?.addSubview(host)
        defer {
            host.removeFromSuperview()
            fixture.window.close()
        }
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNotNil(
            fixture.field.currentEditor(), "Preparing a neighboring Start Page must preserve the current editor")
        let fields = descendants(of: host).compactMap { $0 as? NSTextField }
        let retained = try XCTUnwrap(
            fields.first { $0.accessibilityIdentifier() == "start-page-command-palette-field" })
        XCTAssertFalse(retained.isEditable)
        XCTAssertNil(retained.currentEditor())
        host.rootView = palette.environment(\.spaceContentIsInteractive, true)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(retained.isEditable)
        XCTAssertNotNil(retained.currentEditor(), "The incoming Start Page gains its normal focus when activated")
        host.rootView = palette.environment(\.spaceContentIsInteractive, false)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(retained.currentEditor(), "A departed card must relinquish its editor")
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    func testNativeAcceptanceIsUndoableAndAccessibilityKeepsTypedValueSeparate() throws {
        let fixture = makeEditor()
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        // The unit test has no native key-event boundary. Model the typing
        // event and the separate Tab event with explicit undo groups.
        editor.undoManager?.groupsByEvent = false
        editor.undoManager?.beginUndoGrouping()
        editor.insertText("exa", replacementRange: NSRange(location: 0, length: 0))
        editor.undoManager?.endUndoGrouping()
        fixture.coordinator.editingChanged()
        XCTAssertEqual(editor.string, "exa")
        XCTAssertEqual(fixture.model.urlCompletion?.completedQuery, "example.com/path")
        XCTAssertTrue(fixture.field.accessibilityHelp()?.contains("Press Tab") == true)
        XCTAssertEqual(fixture.field.accessibilityLabel(), "Command Palette")
        XCTAssertEqual(fixture.field.accessibilityIdentifier(), "command-palette-field")
        XCTAssertFalse(fixture.coordinator.suffixLabel.isAccessibilityElement())
        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(fixture.model.acceptURLCompletion())
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(editor.string, "example.com/path")
        editor.undoManager?.undo()
        fixture.coordinator.editingChanged()
        XCTAssertEqual(editor.string, "exa")
        XCTAssertNil(fixture.model.urlCompletion)
    }

    func testNativeSelectionAndMarkedTextPreventAcceptanceWithoutConsumingArrows() throws {
        let fixture = makeEditor()
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        editor.insertText("exa", replacementRange: NSRange(location: 0, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        editor.moveLeft(nil)
        fixture.coordinator.editingChanged()
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertNil(fixture.model.urlCompletion)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.setMarkedText(
            "m", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 3, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertNil(fixture.model.urlCompletion)
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertFalse(fixture.model.acceptURLCompletion())
        XCTAssertEqual(fixture.field.maximumNumberOfLines, 1)
        XCTAssertFalse(fixture.field.cell?.wraps ?? true)
        XCTAssertTrue(fixture.field.cell?.isScrollable ?? false)
    }

    func testRightArrowAcceptsOnlyAtTheEndAndPreservesSelectionCommands() throws {
        let fixture = makeEditor()
        defer { fixture.window.close() }
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        editor.insertText("exa", replacementRange: NSRange(location: 0, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRightAndModifySelection(_:))))
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertTrue(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        XCTAssertEqual(editor.string, "example.com/path")
        XCTAssertFalse(
            fixture.coordinator.control(
                fixture.field, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
    }

    private func makeEditor() -> (
        window: NSWindow, field: NSTextField, coordinator: BrowserPlatformCommandPaletteField.Coordinator,
        model: BrowserCommandPaletteModel
    ) {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Test", symbol: "globe", accent: .indigo, folders: [],
            tabs: [tab], selectedTabID: tab.id)
        let model = BrowserCommandPaletteModel(
            space: space, selectedTabID: tab.id, initialQuery: "", commands: nil, isSourceAvailable: { _ in true },
            selectTab: { _, _ in false }, openURL: { _, _ in false }, dismiss: {})
        let view = BrowserPlatformCommandPaletteField(
            model: model, presentation: .overlay, identifier: "command-palette-field", focused: false)
        let coordinator = view.makeCoordinator()
        let field = view.makeField(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        field.frame = NSRect(x: 10, y: 20, width: 300, height: 32)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        field.selectText(nil)
        return (window, field, coordinator, model)
    }
}

private struct EmptySpacePaletteHost: View {
    let model: BrowserRootModel
    @Namespace private var namespace

    var body: some View {
        BrowserRootCommandPaletteLayer(model: model, shortcuts: nil, commandSurfaceNamespace: namespace)
    }
}
