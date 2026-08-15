import Foundation
import SwiftUI

struct BrowserImportSidebarResultTabRow: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool
    var isMatched = false

    var body: some View {
        HStack(spacing: 8) {
            TabFaviconView(tab: tab, profileID: profileID, size: 18)
            Text(tab.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if isMatched {
                Image(systemName: "equal.circle.fill")
                    .font(.caption)
                    .foregroundStyle(BrowserOnboardingPalette.match)
            }
            if tab.placement == .current, isSelected {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 17)
        .padding(.trailing, 12)
        .frame(height: 40)
        .background(
            isMatched
                ? BrowserOnboardingPalette.match.opacity(0.16)
                : isSelected ? Color.primary.opacity(0.1) : .clear,
            in: .rect(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if isMatched {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        BrowserOnboardingPalette.match.opacity(0.52),
                        lineWidth: 0.75
                    )
            }
        }
        .padding(.horizontal, 8)
        .accessibilityValue(isMatched ? "Matched in source browser" : "In Crest")
    }
}

#Preview("Import Sidebar Result Tab") {
    BrowserImportSidebarResultTabRow(
        tab: BrowserImportPreviewFixture.savedTab,
        profileID: BrowserImportPreviewFixture.sourceSpace.profile.id,
        isSelected: false,
        isMatched: true
    )
    .frame(width: 340)
    .padding()
}
