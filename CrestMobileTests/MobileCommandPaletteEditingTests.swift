import UIKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileCommandPaletteEditingTests: XCTestCase {
    func testStartPageUsesNormalTextInputAndSubmitsSearchesAndURLs() async {
        var openedURLs: [URL] = []
        let fixture = makeEditor(presentation: .embedded) { url in
            openedURLs.append(url)
            return true
        }
        XCTAssertEqual(fixture.field.keyboardType, .default)
        XCTAssertNil(fixture.field.textContentType)
        fixture.field.insertText("kroger pharmacy")
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()
        XCTAssertEqual(fixture.model.query, "kroger pharmacy")
        XCTAssertNil(fixture.model.urlCompletion)
        XCTAssertFalse(fixture.coordinator.textFieldShouldReturn(fixture.field))
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://www.google.com/search?q=kroger%20pharmacy"])
        fixture.field.selectedTextRange = fixture.field.textRange(
            from: fixture.field.beginningOfDocument, to: fixture.field.endOfDocument)
        fixture.field.insertText("example.org")
        fixture.coordinator.editingChanged()
        await fixture.model.waitForPendingResults()
        XCTAssertFalse(fixture.coordinator.textFieldShouldReturn(fixture.field))
        XCTAssertEqual(openedURLs.last?.absoluteString, "https://example.org")
    }

    func testNativeFieldAcceptsCompletionWithoutNavigationAndProvidesTabAction() throws {
        for presentation in [BrowserCommandPalettePresentation.embedded, .overlay] {
            let fixture = makeEditor(presentation: presentation)
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
            XCTAssertEqual(field.keyboardType, presentation == .embedded ? .default : .URL)
            XCTAssertEqual(field.textContentType, presentation == .embedded ? nil : .URL)
            XCTAssertEqual(field.autocorrectionType, .no)
            XCTAssertTrue(field.adjustsFontForContentSizeCategory)
        }
    }

    func testNativeSelectionAndMarkedTextSuppressCompletion() throws {
        for presentation in [BrowserCommandPalettePresentation.embedded, .overlay] {
            let fixture = makeEditor(presentation: presentation)
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
    }

    private func makeEditor(
        presentation: BrowserCommandPalettePresentation = .overlay,
        openURL: @escaping (URL) -> Bool = { _ in
            XCTFail("Unexpected navigation")
            return false
        }
    ) -> (
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
            openURL: { _, url in openURL(url) }, dismiss: {})
        let view = BrowserPlatformCommandPaletteField(
            model: model, presentation: presentation, identifier: "command-palette-field", focused: false)
        let coordinator = view.makeCoordinator()
        let field = view.makeField(coordinator: coordinator)
        return (field, coordinator, model)
    }
}
