import AppKit
import SwiftUI

struct BrowserOnboardingReviewToolbar: View {
    let icon: NSImage?
    let progressLabel: String
    let customize: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Review before importing")
                    .font(
                        BrowserOnboardingTypography.sans(14, weight: .bold)
                    )
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            }

            Spacer(minLength: 8)

            Button(
                "Customize Space",
                systemImage: "paintpalette",
                action: customize
            )
            .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .frame(height: 78)
        .background(BrowserOnboardingPalette.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrowserOnboardingPalette.line)
                .frame(height: 1)
        }
    }
}

#Preview("Review Toolbar") {
    BrowserOnboardingReviewToolbar(
        icon: BrowserOnboardingWindowPreviewFixture.importSource.icon,
        progressLabel: "Space 1 of 1 · Work",
        customize: {}
    )
    .frame(width: 980)
}
