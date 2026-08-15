import SwiftUI

struct BrowserCommandPaletteRowTrailing: View {
    let model: BrowserCommandPaletteModel
    let result: BrowserCommandPaletteResult

    @ViewBuilder
    var body: some View {
        if let foreignSpace = model.foreignSpace(for: result) {
            BrowserSpaceIdentityLabel(
                space: foreignSpace,
                title: foreignSpace.name,
                iconSize: BrowserCommandPaletteMetrics.foreignSpaceIconSize
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if case .command(let command) = result.target,
            let chord = model.commands?.shortcut(for: command)
        {
            Text(verbatim: chord.displayString)
                .font(.caption.weight(.medium).monospaced())
                .foregroundStyle(.secondary)
                .padding(
                    .horizontal,
                    BrowserCommandPaletteMetrics.shortcutHorizontalPadding
                )
                .frame(minHeight: BrowserCommandPaletteMetrics.shortcutMinimumHeight)
                .background(
                    .primary.opacity(
                        BrowserCommandPaletteMetrics.shortcutBackgroundOpacity
                    ),
                    in: .rect(
                        cornerRadius: BrowserCommandPaletteMetrics.shortcutCornerRadius
                    )
                )
                .accessibilityLabel(Text(verbatim: chord.spokenDescription))
        } else if !result.trailing.isEmpty {
            Text(LocalizedStringKey(result.trailing))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Command Palette Row Trailing Content") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )

    VStack(spacing: CrestSpacing.large) {
        HStack {
            Text("Other Space")
            Spacer()
            BrowserCommandPaletteRowTrailing(
                model: model,
                result: BrowserCommandPalettePreviewFixture.foreignSpaceResult
            )
        }
        HStack {
            Text("Shortcut")
            Spacer()
            BrowserCommandPaletteRowTrailing(
                model: model,
                result: BrowserCommandPalettePreviewFixture.commandResult
            )
        }
        HStack {
            Text("Trailing Action")
            Spacer()
            BrowserCommandPaletteRowTrailing(
                model: model,
                result: BrowserCommandPalettePreviewFixture.historyResult
            )
        }
    }
    .frame(width: 420)
    .padding(CrestSpacing.large)
}
