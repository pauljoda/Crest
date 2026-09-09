import AppKit
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteNativeEditingTests: XCTestCase {
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
        let view = BrowserPlatformCommandPaletteField(model: model, identifier: "command-palette-field", focused: false)
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
