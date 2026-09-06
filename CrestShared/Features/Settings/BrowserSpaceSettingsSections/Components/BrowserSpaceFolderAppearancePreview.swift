import SwiftUI

/// An inert example uses the live Space's theme and the sidebar's own fill.
struct BrowserSpaceFolderAppearancePreview: View {
    var space: BrowserSpace? = nil
    var followsHighlightPreference = false

    @State private var isHovered = false
    @AppStorage(BrowserFolderAppearancePreference.alwaysVisibleKey, store: BrowserFolderAppearancePreference.defaults)
    private var alwaysVisible = false

    @AppStorage(BrowserFolderAppearancePreference.showsTabCountsKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsTabCounts = true
    @AppStorage(BrowserFolderAppearancePreference.showsBordersKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsBorders = true

    private var folder: BrowserFolder? { space?.folders.first }
    private var branding: BrowserSpaceBranding {
        space?.branding ?? BrowserSpaceBranding(colors: [.ink], bannerPattern: .solid, readabilityFade: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(space?.name ?? String(localized: "Preview"), systemImage: space?.symbol ?? "sidebar.left")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "folder.fill")
                    Text(folder?.title ?? String(localized: "Example folder"))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if showsTabCounts { Text(2, format: .number) }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                previewTab("Selected tab", symbol: "globe", selected: true)
                previewTab("Another tab", symbol: "doc.text", selected: false)
            }
            .padding(.bottom, BrowserFolderAppearancePolicy.regionInset)
            .modifier(
                BrowserFolderHighlightSurface(
                    color: folder?.color ?? .folderDefault,
                    intensity: branding.folderColorIntensity,
                    textColorMode: branding.textColorMode,
                    showsFill: !followsHighlightPreference || alwaysVisible || isHovered,
                    showsBorders: showsBorders))
        }
        .font(.subheadline)
        .padding(.vertical, 12)
        .frame(maxWidth: 340)
        .background { BrowserSpaceBannerBackground(branding: branding) }
        .clipShape(.rect(cornerRadius: CrestLayout.sidebarControlCornerRadius))
        .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: branding))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            space.map { String(localized: "Folder preview in \($0.name)") } ?? String(localized: "Folder preview")
        )
        .accessibilityIdentifier("space-folder-appearance-preview")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func previewTab(_ title: LocalizedStringKey, symbol: String, selected: Bool) -> some View {
        HStack {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.08), in: .rect(cornerRadius: 8))
                    .padding(.trailing, 6)
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 40)
        .crestInteractiveSurface(
            isSelected: selected, isHovering: false, cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
        .padding(.horizontal, CrestSpacing.small + BrowserFolderLayout.contentsInset)
        .padding(.vertical, BrowserFolderAppearancePolicy.regionInset)
    }
}
