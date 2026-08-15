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

#Preview("Shortcut Settings Controls") {
    let model = BrowserShortcutSettingsPreviewFactory.model()
    BrowserShortcutSettingsControls(
        searchText: .constant("tabs"),
        selectedExtensionSpaceID: .constant(
            model.selectedExtensionSpaceID
        ),
        spaces: model.spaces,
        canReset: true,
        requestReset: {}
    )
    .padding()
    .frame(width: BrowserShortcutSettingsMetrics.maximumContentWidth)
}
