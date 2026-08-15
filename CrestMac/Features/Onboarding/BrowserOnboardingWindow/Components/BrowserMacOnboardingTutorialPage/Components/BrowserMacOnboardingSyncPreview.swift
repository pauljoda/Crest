import SwiftUI

struct BrowserMacOnboardingSyncPreview: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            ZStack {
                Circle()
                    .fill(BrowserOnboardingPalette.butter.opacity(0.34))
                    .frame(width: 260, height: 260)
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 112, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BrowserOnboardingPalette.coral)
            }
            VStack(spacing: 8) {
                Text("One setup, every device")
                    .font(BrowserOnboardingTypography.display(30))
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text(
                    "iCloud carries the result. Each Space keeps its own boundary."
                )
                .font(BrowserOnboardingTypography.sans(14, weight: .medium))
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrowserOnboardingPalette.paper)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(BrowserOnboardingPalette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Crest syncing privately between a Mac and iPhone"
        )
    }
}

#Preview("Sync Artwork") {
    BrowserMacOnboardingSyncPreview()
        .frame(width: 540, height: 480)
}
