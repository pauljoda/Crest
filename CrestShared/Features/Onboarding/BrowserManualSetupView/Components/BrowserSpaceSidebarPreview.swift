import SwiftUI

struct BrowserSpaceSidebarPreview: View {
    let space: BrowserSpace

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
                .background(
                    .regularMaterial,
                    in: .rect(
                        cornerRadius: BrowserManualSetupSidebarPreviewMetrics
                            .addressCornerRadius,
                        style: .continuous
                    )
                )
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
                                tabs: space.pinnedTabs,
                                assignment: BrowserSpaceRuntimeAssignment(
                                    space: space
                                ),
                                selectedTabID: space.selectedTabID,
                                select: { _ in }
                            )
                        }
                        BrowserSpaceSidebarSection(
                            title: "SAVED",
                            tabs: space.unfiledSavedTabs,
                            profileID: space.profile.id,
                            selectedTabID: space.selectedTabID
                        )
                        BrowserSpaceSidebarSection(
                            title: "OPEN TABS",
                            tabs: space.currentTabs,
                            profileID: space.profile.id,
                            selectedTabID: space.selectedTabID
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

#Preview("Space Sidebar Preview") {
    BrowserSpaceSidebarPreview(
        space: BrowserManualSetupPreviewFixture.space
    )
    .frame(width: 330, height: 500)
}
