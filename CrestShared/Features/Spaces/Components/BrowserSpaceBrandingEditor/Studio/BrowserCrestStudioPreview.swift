import SwiftUI

/// The production artwork and sidebar components, detached from browsing and persistence.
struct BrowserCrestStudioPreview: View {
    let branding: BrowserSpaceBranding
    let symbol: String
    var name: String = ""
    var space: BrowserSpace? = nil
    var compact = false
    var showsSidebar = true
    var heroSize: CGFloat = 140
    var sidebarHeight: CGFloat = 190
    @State private var sample = BrowserSession.showcase.spaces[0]

    private var preview: BrowserSpace {
        var value = space ?? sample
        value.branding = branding
        value.symbol = symbol
        value.name = name.isEmpty ? String(localized: "Your Space") : name
        return value
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                BrowserSpaceIdentityIcon(space: preview, size: compact ? 96 : heroSize)
                Text(preview.name).font(.headline).lineLimit(1)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background { BrowserSpaceBannerBackground(branding: branding) }
            .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: branding))
            .clipShape(.rect(cornerRadius: 18))

            if !compact && showsSidebar {
                VStack(spacing: 4) {
                    BrowserLookAndFeelAddressPreview(space: preview, showsBackground: false)
                        .padding(.horizontal, 8).padding(.top, 10)
                    BrowserSpaceHeader(
                        space: preview, isPrivateBrowsing: false, isSavedTabsExpanded: .constant(true),
                        capabilities: BrowserInteractionCapabilities(
                            supportsTouch: BrowserSidebarDensityPolicy.usesTouch,
                            pairsRowWithPromotedSurface: false, supportsOrganization: false),
                        actions: BrowserSpaceHeaderActions(
                            openNewTab: {}, createFolder: {}, showHistory: {}, cleanup: {}))
                    BrowserSidebarCustomizationPreview(
                        space: preview, showsPins: false, showsCurrentTabs: false, showsBackground: false)
                }
                .frame(height: sidebarHeight, alignment: .top)
                .clipped()
                .background { BrowserSpaceBannerBackground(branding: branding) }
                .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: branding))
                .clipShape(.rect(cornerRadius: 16))
                .allowsHitTesting(false)
                .accessibilityLabel("Actual sidebar preview")
            }
            Text("Changes appear live in your Space.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BrowserCrestStudioMark: View {
    let branding: BrowserSpaceBranding
    let symbol: String
    var size: CGFloat
    @State private var sample = BrowserSession.showcase.spaces[0]
    var body: some View {
        var space = sample
        space.branding = branding
        space.symbol = symbol
        return BrowserSpaceIdentityIcon(space: space, size: size)
    }
}
