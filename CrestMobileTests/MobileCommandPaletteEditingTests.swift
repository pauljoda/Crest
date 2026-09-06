import UIKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileCommandPaletteEditingTests: XCTestCase {
    func testNativeFieldAcceptsCompletionWithoutNavigationAndProvidesTabAction() throws {
        let fixture = makeEditor()
        let field = fixture.field
        field.insertText("exa")
        fixture.coordinator.editingChanged()
        XCTAssertEqual(field.text, "exa")
        XCTAssertEqual(fixture.model.urlCompletion?.completedQuery, "example.com/path")
        XCTAssertEqual(field.accessibilityLabel, "Command Palette")
        XCTAssertEqual(field.accessibilityIdentifier, "command-palette-field")
        XCTAssertTrue(
            field.keyCommands?.contains { $0.input == "\t" && $0.discoverabilityTitle == "Accept URL completion" }
                == true)
        let rightArrow = try XCTUnwrap(field.keyCommands?.first { $0.input == UIKeyCommand.inputRightArrow })
        XCTAssertEqual(rightArrow.modifierFlags, [])
        field.perform(rightArrow.action, with: rightArrow)
        XCTAssertEqual(field.text, "example.com/path")
        XCTAssertEqual(fixture.model.query, "example.com/path")
        XCTAssertEqual(field.keyboardType, .URL)
        XCTAssertEqual(field.autocorrectionType, .no)
        XCTAssertTrue(field.adjustsFontForContentSizeCategory)
    }

    func testNativeSelectionAndMarkedTextSuppressCompletion() throws {
        let fixture = makeEditor()
        let field = fixture.field
        field.insertText("exa")
        fixture.coordinator.editingChanged()
        field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
        fixture.coordinator.editingChanged()
        XCTAssertNil(fixture.model.urlCompletion)
        XCTAssertFalse(field.keyCommands?.contains { $0.input == UIKeyCommand.inputRightArrow } == true)
        XCTAssertFalse(fixture.model.acceptURLCompletion())
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        field.setMarkedText("m", selectedRange: NSRange(location: 1, length: 0))
        fixture.coordinator.editingChanged()
        XCTAssertNotNil(field.markedTextRange)
        XCTAssertNil(fixture.model.urlCompletion)
        XCTAssertFalse(fixture.model.acceptURLCompletion())
        XCTAssertFalse(fixture.coordinator.textFieldShouldReturn(field))
    }

    private func makeEditor() -> (
        field: BrowserPlatformCommandPaletteField.CompletionField,
        coordinator: BrowserPlatformCommandPaletteField.Coordinator, model: BrowserCommandPaletteModel
    ) {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Test", symbol: "globe", accent: .indigo, folders: [],
            tabs: [tab], selectedTabID: tab.id)
        let model = BrowserCommandPaletteModel(
            space: space, selectedTabID: tab.id, initialQuery: "", commands: nil, isSourceAvailable: { _ in true },
            selectTab: { _, _ in
                XCTFail("Unexpected navigation")
                return false
            },
            openURL: { _, _ in
                XCTFail("Unexpected navigation")
                return false
            }, dismiss: {})
        let view = BrowserPlatformCommandPaletteField(model: model, identifier: "command-palette-field", focused: false)
        let coordinator = view.makeCoordinator()
        let field = view.makeField(coordinator: coordinator)
        return (field, coordinator, model)
    }
}
