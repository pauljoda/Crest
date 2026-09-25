import SwiftUI

struct BrowserSpaceSidebarPreview: View {
    let space: BrowserSpace
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(CrestCore.self) private var core: CrestCore?

    /// No window shows a previewed Space, so it highlights the tab the core
    /// would show first.
    private var selectedTabID: TabID? { core?.fallbackTabID(in: space) }

    var body: some View {
        ZStack {
            BrowserSpaceBannerBackground(branding: space.branding)

            VStack(spacing: 0) {
                HStack(
                    spacing: BrowserManualSetupSidebarPreviewMetrics.addressSpacing
                ) {
                    Image(systemName: "magnifyingglass")
                    Text("Search or enter website")
                        .lineLimit(1)
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(
                    .horizontal,
                    BrowserManualSetupSidebarPreviewMetrics
                        .addressHorizontalPadding
                )
                .frame(
                    height: BrowserManualSetupSidebarPreviewMetrics.addressHeight
                )
                .browserAddressFieldSurface(progress: 0, isLoading: false, isEditing: false, branding: space.branding)
                .padding(
                    BrowserManualSetupSidebarPreviewMetrics.addressOuterPadding
                )

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: BrowserManualSetupSidebarPreviewMetrics
                            .contentSpacing
                    ) {
                        if !space.pinnedTabs.isEmpty {
                            PinnedTabGrid(
                                drafts: space.pinnedTabs,
                                assignment: BrowserSpaceRuntimeAssignment(space: space),
                                selectedTabID: selectedTabID,
                                capabilities: capabilities
                            )
                        }
                        BrowserSpaceSidebarSection(
                            title: "SAVED",
                            tabs: space.unfiledSavedTabs,
                            profileID: space.profile.id,
                            selectedTabID: selectedTabID
                        )
                        BrowserSpaceSidebarSection(
                            title: "OPEN TABS",
                            tabs: space.currentTabs,
                            profileID: space.profile.id,
                            selectedTabID: selectedTabID
                        )
                    }
                    .padding(
                        .horizontal,
                        BrowserManualSetupSidebarPreviewMetrics
                            .contentHorizontalPadding
                    )
                    .padding(
                        .bottom,
                        BrowserManualSetupSidebarPreviewMetrics
                            .contentBottomPadding
                    )
                }
            }
        }
        .clipShape(
            .rect(
                cornerRadius: BrowserManualSetupSidebarPreviewMetrics
                    .frameCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: BrowserManualSetupSidebarPreviewMetrics
                    .frameCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                Color.primary.opacity(
                    BrowserManualSetupSidebarPreviewMetrics.frameStrokeOpacity
                ),
                lineWidth: BrowserManualSetupSidebarPreviewMetrics
                    .frameStrokeWidth
            )
        }
        .environment(
            \.colorScheme,
            BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
        )
        .allowsHitTesting(false)
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: space, isUnlocked: true))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Branding preview of \(space.name)")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let mode =
            switch space.branding.themeMode {
            case .banner: String(localized: "Banner")
            case .gradient: String(localized: "Gradient")
            }
        let colors = space.branding.colors.map(\.title).joined(separator: ", ")
        return "\(mode), \(colors), \(space.branding.iconStyle.title)"
    }
}
