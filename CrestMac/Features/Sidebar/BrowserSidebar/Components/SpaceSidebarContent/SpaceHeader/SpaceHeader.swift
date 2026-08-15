import SwiftUI

struct SpaceHeader: View {
    let space: BrowserSpace
    let isPrivateBrowsing: Bool
    @Binding var isSavedTabsExpanded: Bool
    let openNewTab: () -> Void
    let createFolder: () -> Void
    let showHistory: () -> Void
    let showExtensions: () -> Void
    let cleanup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleSavedTabs) {
                HStack(spacing: CrestSpacing.small) {
                    Group {
                        if BrowserSpaceHeaderIconPolicy.showsDisclosure(
                            isSavedTabsExpanded: isSavedTabsExpanded
                        ) {
                            Image(systemName: "chevron.right")
                                .font(
                                    .system(
                                        size: BrowserSidebarMetrics
                                            .spaceHeaderDisclosurePointSize,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        } else {
                            BrowserSpaceIdentityIcon(
                                space: space,
                                size: BrowserSidebarMetrics.spaceHeaderIconSize
                            )
                            .transition(.opacity)
                        }
                    }
                    .frame(
                        width: BrowserSidebarMetrics.spaceHeaderIconSize,
                        height: BrowserSidebarMetrics.spaceHeaderIconSize
                    )

                    Text(space.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: CrestSpacing.small)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(space.name) saved tabs")
            .accessibilityValue(isSavedTabsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(
                isSavedTabsExpanded
                    ? "Collapses saved tabs"
                    : "Expands saved tabs"
            )

            SpaceHeaderActionsMenu(
                isPrivateBrowsing: isPrivateBrowsing,
                openNewTab: openNewTab,
                createFolder: createFolder,
                showHistory: showHistory,
                showExtensions: showExtensions,
                cleanup: cleanup
            )
        }
        .padding(.leading, CrestSpacing.small)
        .padding(.trailing, CrestSpacing.extraSmall)
        .frame(height: CrestLayout.sidebarRowHeight)
        .crestHoverSurface(
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
        .padding(.horizontal, CrestSpacing.small)
    }

    private func toggleSavedTabs() {
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.disclosure,
                reduceMotion: reduceMotion
            )
        ) {
            isSavedTabsExpanded.toggle()
        }
    }
}

#Preview("Space Header — Expanded", traits: .sizeThatFitsLayout) {
    @Previewable @State var isExpanded = true
    SpaceHeader(
        space: BrowserSidebarPreviewFixture.space,
        isPrivateBrowsing: false,
        isSavedTabsExpanded: $isExpanded,
        openNewTab: {},
        createFolder: {},
        showHistory: {},
        showExtensions: {},
        cleanup: {}
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}

#Preview("Space Header — Collapsed", traits: .sizeThatFitsLayout) {
    @Previewable @State var isExpanded = false
    SpaceHeader(
        space: BrowserSidebarPreviewFixture.space,
        isPrivateBrowsing: false,
        isSavedTabsExpanded: $isExpanded,
        openNewTab: {},
        createFolder: {},
        showHistory: {},
        showExtensions: {},
        cleanup: {}
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}
