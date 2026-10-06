import SwiftUI

struct BrowserInstalledImportSourceGrid: View {
    let sources: [BrowserInstalledImportSource]
    let isSelected: (BrowserInstalledImportSource) -> Bool
    let isLocked: Bool
    let accessLabel: (BrowserInstalledImportSource) -> String
    let toggleSelection: (BrowserInstalledImportSource) -> Void

    private var rows: [[BrowserInstalledImportSource]] {
        stride(from: 0, to: sources.count, by: 3).map { start in
            Array(sources[start..<min(start + 3, sources.count)])
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: 16) {
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
                        .frame(width: 260)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: 940)
    }
}

private struct BrowserInstalledImportSourceCard: View {
    let source: BrowserInstalledImportSource
    let isSelected: Bool
    let isLocked: Bool
    let accessLabel: String
    let toggleSelection: () -> Void

    var body: some View {
        Button(action: toggleSelection) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(nsImage: source.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .accessibilityHidden(true)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(BrowserOnboardingPalette.coral)
                            .accessibilityHidden(true)
                    }
                }
                Text(source.title)
                    .font(
                        BrowserOnboardingTypography.sans(17, weight: .bold)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text(source.application.description)
                    .font(
                        BrowserOnboardingTypography.sans(13, weight: .medium)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Text(accessLabel)
                    .font(
                        BrowserOnboardingTypography.sans(11, weight: .bold)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.coral)
            }
            .frame(maxWidth: .infinity, minHeight: 172, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? BrowserOnboardingPalette.butter.opacity(0.24)
                            : BrowserOnboardingPalette.paper
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? BrowserOnboardingPalette.ink
                            : BrowserOnboardingPalette.line,
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel("Import from \(source.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(
            source.hasDetectedData
                ? "Review its Spaces and tabs"
                : "Crest locates the browser data folder and asks for one-time read access"
        )
    }
}
