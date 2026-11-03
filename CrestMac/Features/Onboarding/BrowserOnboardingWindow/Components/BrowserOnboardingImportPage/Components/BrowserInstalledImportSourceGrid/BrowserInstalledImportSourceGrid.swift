import SwiftUI

struct BrowserInstalledImportSourceGrid: View {
    let sources: [BrowserInstalledImportSource]
    let isSelected: (BrowserInstalledImportSource) -> Bool
    let isLocked: Bool
    let accessLabel: (BrowserInstalledImportSource) -> String?
    let toggleSelection: (BrowserInstalledImportSource) -> Void

    private var rows: [[BrowserInstalledImportSource]] {
        stride(from: 0, to: sources.count, by: 3).map { start in
            Array(sources[start..<min(start + 3, sources.count)])
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: 20) {
                    ForEach(row) { source in
                        BrowserInstalledImportSourceCard(
                            source: source,
                            isSelected: isSelected(source),
                            isLocked: isLocked,
                            accessLabel: accessLabel(source),
                            toggleSelection: {
                                toggleSelection(source)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// One browser as a tile: its icon and name, and what reading it takes once
/// setup knows.
private struct BrowserInstalledImportSourceCard: View {
    let source: BrowserInstalledImportSource
    let isSelected: Bool
    let isLocked: Bool
    let accessLabel: String?
    let toggleSelection: () -> Void

    var body: some View {
        CrestSelectableCard(
            isSelected: isSelected, accessibilityLabel: Text("Import from \(source.title)"), density: .compact,
            tint: CrestBrandPalette.butter, action: toggleSelection
        ) {
            VStack(spacing: 12) {
                Image(nsImage: source.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
                Text(source.title)
                    .font(CrestTypography.sans(15, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .lineLimit(1)
                Text(accessLabel ?? "")
                    .font(CrestTypography.sans(11, weight: .medium))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
                    .lineLimit(1)
                    .frame(height: 14)
            }
            .frame(width: 180, height: 160)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CrestBrandPalette.ink)
                        .frame(width: 22, height: 22)
                        .background(CrestBrandPalette.butter, in: .circle)
                        .padding(CrestSpacing.extraExtraSmall)
                        .accessibilityHidden(true)
                }
            }
        }
        .fixedSize()
        .disabled(isLocked)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(accessibilityHint)
    }

    /// What going on with this browser does: an unscanned browser's data is
    /// read then and may need access, found data is reviewed, and otherwise
    /// Crest asks for the folder.
    private var accessibilityHint: Text {
        guard source.detectedPayload != nil else {
            return Text("Crest reads its data when you continue, which may ask for access")
        }
        return source.hasDetectedData
            ? Text("Review its Spaces and tabs")
            : Text("Crest locates the browser data folder and asks for one-time read access")
    }
}
