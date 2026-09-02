import SwiftUI

struct MobileBrowserSidebarSpaceSurface: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let space: BrowserSpace
    let isSelected: Bool
    let contentInsets: EdgeInsets

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLocked = configuration.context.spaceAccess.isLocked(space)
        let backdropStyle = MobileBrowserSidebarBackdropPolicy.style(isPaging: false)

        ZStack {
            MobileBrowserSidebarSpaceContent(
                configuration: configuration,
                space: space,
                isSelected: isSelected
            )
            .environment(\.colorScheme, spaceColorScheme)
            .blur(
                radius: isLocked
                    ? BrowserSidebarMetrics.lockedSpaceBlurRadius
                    : 0
            )
            .redacted(reason: isLocked ? .placeholder : [])
            .allowsHitTesting(!isLocked)
            .accessibilityHidden(isLocked)

            if isLocked {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: configuration.context.availableSpaces,
                    accessController: configuration.context.spaceAccess,
                    selectSpace: selectUnlockedSpace,
                    presentation: .contentOverlay
                )
                // The horizontal pager consumes the safe area. Carry its
                // chrome clearances into this nested vertical lock scroller.
                .padding(.top, contentInsets.top)
                .padding(.bottom, contentInsets.bottom)
                .containerRelativeFrame(.vertical)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if MobileBrowserSidebarBackdropPolicy.showsPageBackdrop(
                showsPageBackdrop: configuration.showsPageBackdrop,
                isPaging: false,
                isSelected: isSelected
            ) {
                BrowserSpaceBannerBackground(
                    branding: MobileBrowserSidebarBackdropPolicy.branding(
                        for: space
                    )
                )
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
        .overlay {
            RoundedRectangle(
                cornerRadius: backdropStyle.cornerRadius,
                style: .continuous
            )
            .strokeBorder(
                Color.primary.opacity(backdropStyle.outlineOpacity),
                lineWidth: 1
            )
        }
        .padding(.horizontal, backdropStyle.horizontalInset)
        .padding(.vertical, backdropStyle.verticalInset)
    }

    private var spaceColorScheme: ColorScheme {
        guard MobileBrowserSidebarAppearancePolicy.usesSpaceForeground() else {
            return colorScheme
        }
        return BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
    }

    private func selectUnlockedSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard
            let candidate = configuration.context.browser.space(
                matching: assignment
            ),
            !configuration.context.spaceAccess.isLocked(candidate)
        else { return }
        configuration.context.selectSpace(assignment.spaceID)
    }
}
