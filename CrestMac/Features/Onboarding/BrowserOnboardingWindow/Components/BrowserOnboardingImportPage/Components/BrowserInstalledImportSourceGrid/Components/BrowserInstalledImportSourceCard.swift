import SwiftUI

struct BrowserInstalledImportSourceCard: View {
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

#Preview("Installed Browser Card") {
    BrowserInstalledImportSourceCard(
        source: BrowserOnboardingWindowPreviewFixture.importSource,
        isSelected: true,
        isLocked: false,
        accessLabel: "Ready to review",
        toggleSelection: {}
    )
    .frame(width: 260)
    .padding()
    .background(BrowserOnboardingPalette.parchment)
}
