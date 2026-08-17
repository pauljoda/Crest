import SwiftUI

struct BrowserInstalledImportSourceGrid: View {
    let sources: [BrowserInstalledImportSource]
    let selectedApplications: Set<BrowserImportApplication>
    let isLocked: Bool
    let accessLabel: (BrowserInstalledImportSource) -> String
    let toggleSelection: (BrowserImportApplication) -> Void

    private var rows: [[BrowserInstalledImportSource]] {
        stride(from: 0, to: sources.count, by: 3).map { start in
            Array(sources[start..<min(start + 3, sources.count)])
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: 16) {
                    ForEach(row) { source in
                        BrowserInstalledImportSourceCard(
                            source: source,
                            isSelected: selectedApplications.contains(
                                source.application
                            ),
                            isLocked: isLocked,
                            accessLabel: accessLabel(source),
                            toggleSelection: {
                                toggleSelection(source.application)
                            }
                        )
                        .frame(width: 260)
                    }
                }
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
                Text(source.application.name)
                    .font(
                        BrowserOnboardingTypography.sans(17, weight: .bold)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text(source.application.sourceDescription)
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
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
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
        .accessibilityLabel("Import from \(source.application.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(
            source.hasDetectedData
                ? "Review its Spaces and tabs"
                : "Crest locates the browser data folder and asks for one-time read access"
        )
    }
}
