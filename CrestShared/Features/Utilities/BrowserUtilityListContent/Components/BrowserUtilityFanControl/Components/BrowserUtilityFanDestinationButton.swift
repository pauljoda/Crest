import SwiftUI

struct BrowserUtilityFanDestinationButton: View {
    let surface: BrowserUtilitySurface
    let selectedSurface: BrowserUtilitySurface?
    let badgeColor: Color
    let downloads: [BrowserDownloadItem]
    let newDownloadCount: Int
    let glassNamespace: Namespace.ID
    let select: (BrowserUtilitySurface) -> Void

    var body: some View {
        Button {
            select(surface)
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(.primary)
                .frame(
                    width: BrowserUtilitySwitcherLayout.buttonSize,
                    height: BrowserUtilitySwitcherLayout.buttonSize
                )
                .contentShape(.circle)
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .buttonStyle(
            GlassButtonStyle(
                selectedSurface == surface
                    ? .regular.tint(badgeColor)
                    : .regular
            )
        )
        .glassEffectUnion(id: surface, namespace: glassNamespace)
        .overlay(alignment: .topTrailing) {
            if surface == .downloads, newDownloadCount > 0 {
                Text("\(min(newDownloadCount, 99))")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .browserReadableForeground(over: downloadBadgeColor)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 13, minHeight: 13)
                    .background(downloadBadgeColor, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .help(Text(surface.title))
        .accessibilityLabel(Text(surface.title))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(selectedSurface == surface ? .isSelected : [])
        .accessibilityIdentifier(BrowserUtilityAccessibilityID.destination(surface))
    }

    private var symbol: String {
        guard surface == .downloads else { return surface.systemImage }
        if downloads.contains(where: { $0.state.needsAttention }) {
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
        if downloads.contains(where: { $0.state.isInProgress }) {
            return "arrow.down.circle"
        }
        return "arrow.down.circle.fill"
    }

    private var accessibilityValue: LocalizedStringResource {
        if selectedSurface == surface {
            return BrowserUtilityPresentation.selected
        }
        guard surface == .downloads else {
            return BrowserUtilityPresentation.notSelected
        }
        return BrowserUtilityPresentation.downloadCount(downloads.count)
    }

    private var downloadBadgeColor: Color {
        downloads.contains(where: { $0.state.needsAttention }) ? .red : badgeColor
    }
}
