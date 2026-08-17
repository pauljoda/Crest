import SwiftUI

struct MobileBrowserSidebarSpaceSurface: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let space: BrowserSpace
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLocked = configuration.spaceAccess.isLocked(space)
        let backdropStyle = MobileBrowserSidebarBackdropPolicy.style(isPaging: false)

        ZStack {
            MobileBrowserSidebarSpaceContent(
                configuration: configuration,
                space: space,
                isSelected: isSelected
            )
            .environment(\.colorScheme, spaceColorScheme)
            .blur(radius: isLocked ? 12 : 0)
            .redacted(reason: isLocked ? .placeholder : [])
            .allowsHitTesting(!isLocked)
            .accessibilityHidden(isLocked)

            if isLocked {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: BrowserSidebarAccessPolicy.availableSpaces(
                        in: configuration.browser
                    ),
                    accessController: configuration.spaceAccess,
                    selectSpace: selectUnlockedSpace,
                    presentation: .contentOverlay
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if MobileBrowserSidebarBackdropPolicy.showsPageBackdrop(
                for: configuration.mode,
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
        guard
            MobileBrowserSidebarAppearancePolicy.usesSpaceForeground(
                for: configuration.mode
            )
        else { return colorScheme }
        return BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
    }

    private func selectUnlockedSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard let candidate = configuration.browser.space(matching: assignment),
            !configuration.spaceAccess.isLocked(candidate)
        else { return }
        configuration.selectSpace(assignment.spaceID)
    }
}
