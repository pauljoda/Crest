import AppKit
import SwiftUI

struct BrowserShortcutSettingsControls: View {
    @Binding var searchText: String
    @Binding var selectedExtensionSpaceID: SpaceID?

    let spaces: [BrowserSpace]
    let canReset: Bool
    let requestReset: () -> Void

    var body: some View {
        HStack(spacing: BrowserShortcutSettingsMetrics.controlSpacing) {
            BrowserShortcutSearchField(
                text: $searchText,
                placeholder: BrowserShortcutSettingsPresentation.searchPrompt,
                identifier: BrowserShortcutSettingsAccessibilityID.search
            )
            .frame(maxWidth: .infinity)
            .frame(height: BrowserShortcutSettingsMetrics.searchFieldHeight)

            if spaces.count > 1 {
                Picker(
                    BrowserShortcutSettingsPresentation.extensionSpace,
                    selection: $selectedExtensionSpaceID
                ) {
                    ForEach(spaces) { space in
                        Text(space.name).tag(Optional(space.id))
                    }
                }
                .labelsHidden()
                .frame(width: BrowserShortcutSettingsMetrics.spacePickerWidth)
                .accessibilityLabel(
                    Text(BrowserShortcutSettingsPresentation.extensionSpace)
                )
            }

            Button(
                BrowserShortcutSettingsPresentation.resetCrest,
                systemImage: "arrow.counterclockwise",
                action: requestReset
            )
            .buttonStyle(.bordered)
            .disabled(!canReset)
            .accessibilityIdentifier(
                BrowserShortcutSettingsAccessibilityID.resetAll
            )
        }
    }
}

private struct BrowserShortcutSearchField: NSViewRepresentable {
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

@MainActor
private final class BrowserShortcutSearchFieldCoordinator:
    NSObject,
    NSSearchFieldDelegate
{
    var text: Binding<String>

    init(text: Binding<String>) {
        self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else {
            return
        }
        text.wrappedValue = field.stringValue
    }
}
