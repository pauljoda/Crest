import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteNativeEditingTests: XCTestCase {
    func testDismantlingFieldReleasesCompletionHostWithoutDisruptingItsSuccessor() async throws {
        weak var oldLabel: BrowserPlatformCommandPaletteField.CompletionLabel?
        let successor = try autoreleasepool {
            let fixture = makeEditor()
            let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
            fixture.coordinator.controlTextDidBeginEditing(
                Notification(name: NSControl.textDidBeginEditingNotification, object: fixture.field))
            oldLabel = fixture.coordinator.suffixLabel
            XCTAssertTrue(oldLabel?.superview === editor)
            let unrelated = NSView()
            editor.addSubview(unrelated)

            // Removing a representable need not send the text delegate an
            // end-editing callback. The shared editor outlives this field.
            BrowserPlatformCommandPaletteField.dismantleNSView(fixture.field, coordinator: fixture.coordinator)
            XCTAssertNil(oldLabel?.superview)
            XCTAssertNil(oldLabel?.nextResponder)
            XCTAssertNil(fixture.coordinator.field)
            XCTAssertNil(fixture.field.delegate)
            XCTAssertTrue(unrelated.superview === editor)
            let oldQuery = fixture.model.query
            editor.string = "detached editor text"
            NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: editor)
            XCTAssertEqual(fixture.model.query, oldQuery)

            let view = BrowserPlatformCommandPaletteField(
                model: fixture.model, presentation: .overlay, identifier: "successor-field", focused: false)
            let coordinator = view.makeCoordinator()
            let field = view.makeField(coordinator: coordinator)
            field.frame = fixture.field.frame
            fixture.window.contentView?.addSubview(field)
            fixture.window.makeFirstResponder(field)
            field.selectText(nil)
            let nextEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            coordinator.controlTextDidBeginEditing(
                Notification(name: NSControl.textDidBeginEditingNotification, object: field))
            XCTAssertTrue(nextEditor === editor)
            XCTAssertTrue(coordinator.suffixLabel.superview === editor)

            // Delayed disposal of an old field must not clear a newer field's
            // callback, responder link, delegate or selection observer.
            BrowserPlatformCommandPaletteField.dismantleNSView(fixture.field, coordinator: fixture.coordinator)
            XCTAssertTrue(field.delegate === coordinator)
            XCTAssertTrue(coordinator.suffixLabel.nextResponder === editor)
            editor.insertText("exa", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            coordinator.editingChanged()
            XCTAssertTrue(fixture.model.acceptURLCompletion())
            XCTAssertEqual(editor.string, "example.com/path")

            // The same coordinator can detach and rejoin normal editing.
            coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
            XCTAssertNil(coordinator.suffixLabel.nextResponder)
            coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification))
            XCTAssertTrue(coordinator.suffixLabel.superview === editor)
            XCTAssertTrue(coordinator.suffixLabel.nextResponder === editor)
            return (window: fixture.window, field: field, coordinator: coordinator, editor: editor)
        }
        defer {
            BrowserPlatformCommandPaletteField.dismantleNSView(successor.field, coordinator: successor.coordinator)
            successor.window.close()
        }
        for _ in 0..<20 where oldLabel != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(oldLabel, "The surviving field editor must not retain a disposed completion hosting view")
        XCTAssertTrue(successor.field.currentEditor() === successor.editor)
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
