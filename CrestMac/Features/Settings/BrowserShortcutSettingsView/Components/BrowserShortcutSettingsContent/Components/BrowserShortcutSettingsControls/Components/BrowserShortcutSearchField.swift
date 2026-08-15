import AppKit
import SwiftUI

struct BrowserShortcutSearchField: NSViewRepresentable {
    @Environment(\.locale) private var locale

    @Binding var text: String

    let placeholder: LocalizedStringResource
    let identifier: String

    func makeCoordinator() -> BrowserShortcutSearchFieldCoordinator {
        BrowserShortcutSearchFieldCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = BrowserShortcutLocalization.string(
            placeholder,
            locale: locale
        )
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = BrowserShortcutLocalization.string(
            placeholder,
            locale: locale
        )
        context.coordinator.text = $text
    }
}

#Preview("Shortcut Search") {
    @Previewable @State var text = "tabs"

    BrowserShortcutSearchField(
        text: $text,
        placeholder: BrowserShortcutSettingsPresentation.searchPrompt,
        identifier: BrowserShortcutSettingsAccessibilityID.search
    )
    .frame(width: 360)
    .padding()
}
