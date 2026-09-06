import SwiftUI

struct BrowserCommandPaletteSearchField: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let queryIsFocused: FocusState<Bool>.Binding

    @ScaledMetric(relativeTo: .title2) private var fieldHeight = 32.0

    var body: some View {
        HStack(spacing: BrowserCommandPaletteMetrics.searchFieldSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            BrowserPlatformCommandPaletteField(
                model: model,
                identifier: presentation == .overlay
                    ? "command-palette-field" : "start-page-command-palette-field",
                focused: queryIsFocused.wrappedValue
            )
            .focused(queryIsFocused)
            .frame(height: fieldHeight)

            if let completion = model.urlCompletion {
                Button {
                    model.acceptURLCompletion()
                } label: {
                    #if os(macOS)
                        Label("Tab", systemImage: "arrow.right.to.line")
                            .font(.caption)
                    #else
                        Image(systemName: "arrow.right.to.line")
                    #endif
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Accept URL completion (Tab or Right Arrow)")
                .accessibilityLabel("Accept URL completion")
                .accessibilityValue(completion.acceptedQuery)
                .accessibilityHint("Fills the address without opening it. Press Tab or Right Arrow to accept.")
                .accessibilityIdentifier("command-palette-accept-completion")
            }

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
