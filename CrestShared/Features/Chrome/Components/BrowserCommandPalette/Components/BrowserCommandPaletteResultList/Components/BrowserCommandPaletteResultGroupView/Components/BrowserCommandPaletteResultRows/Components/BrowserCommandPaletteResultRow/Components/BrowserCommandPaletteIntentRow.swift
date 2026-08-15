import SwiftUI

struct BrowserCommandPaletteIntentRow: View {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteIndexedResult

    var body: some View {
        Button {
            model.activate(item.result)
        } label: {
            HStack(spacing: BrowserCommandPaletteMetrics.rowSpacing) {
                Group {
                    if let provider = item.result.searchProvider {
                        BrowserSearchProviderIcon(
                            provider: provider,
                            size: BrowserCommandPaletteMetrics.intentSymbolPointSize
                        )
                    } else {
                        Image(systemName: item.result.symbol)
                            .font(
                                .system(
                                    size: BrowserCommandPaletteMetrics.intentSymbolPointSize,
                                    weight: .semibold
                                )
                            )
                    }
                }
                .frame(
                    width: BrowserCommandPaletteMetrics.rowIconContainerSize,
                    height: BrowserCommandPaletteMetrics.rowIconContainerSize
                )
                .background(
                    .primary.opacity(
                        BrowserCommandPaletteMetrics.rowIconBackgroundOpacity
                    ),
                    in: .rect(
                        cornerRadius: BrowserCommandPaletteMetrics.rowIconCornerRadius
                    )
                )
                .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: BrowserCommandPaletteMetrics.rowTextSpacing
                ) {
                    Text(verbatim: item.result.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: item.result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: BrowserCommandPaletteMetrics.rowSpacing)

                Image(systemName: "arrow.turn.down.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(
            BrowserCommandPaletteRowButtonStyle(
                isSelected: model.selectedResultIndex == item.index
            )
        )
        .accessibilityLabel(Text(verbatim: item.result.title))
        .accessibilityValue(Text(verbatim: item.result.subtitle))
        .accessibilityIdentifier("command-palette-primary-action")
        .browserCommandPaletteHoverSelection(model: model, index: item.index)
    }
}

#Preview("Command Palette Intent Row") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )

    BrowserCommandPaletteIntentRow(
        model: model,
        item: BrowserCommandPalettePreviewFixture.intentItem
    )
    .frame(width: BrowserCommandPaletteMetrics.maximumCardWidth)
    .padding(CrestSpacing.large)
}
