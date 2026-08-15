import SwiftUI

struct BrowserCommandPaletteSearchField: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let queryIsFocused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var model = model

        HStack(spacing: BrowserCommandPaletteMetrics.searchFieldSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search or Enter URL…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title2)
                .lineLimit(1)
                .modifier(BrowserPlatformAddressInputModifier())
                .focused(queryIsFocused)
                .onSubmit(model.activateSelectedResult)
                .accessibilityLabel("Command Palette")
                .accessibilityIdentifier(
                    presentation == .overlay
                        ? "command-palette-field"
                        : "start-page-command-palette-field"
                )

            if presentation == .overlay {
                Button("Close", systemImage: "xmark", action: model.dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, BrowserCommandPaletteMetrics.searchFieldHorizontalPadding)
        .frame(minHeight: BrowserCommandPaletteMetrics.searchFieldMinimumHeight)
    }
}

#Preview("Command Palette Search Field") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )
    @Previewable @FocusState var queryIsFocused: Bool

    BrowserCommandPaletteSearchField(
        model: model,
        presentation: .overlay,
        queryIsFocused: $queryIsFocused
    )
    .frame(width: 640)
    .background(
        .regularMaterial,
        in: .rect(cornerRadius: BrowserCommandPaletteMetrics.cardCornerRadius)
    )
    .padding(CrestSpacing.large)
}
