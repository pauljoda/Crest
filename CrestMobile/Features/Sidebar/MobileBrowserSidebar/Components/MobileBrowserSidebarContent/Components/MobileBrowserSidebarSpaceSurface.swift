import SwiftUI

struct MobileBrowserSidebarSpaceSurface: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let space: BrowserSpace
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLocked = configuration.context.spaceAccess.isLocked(space)

        MobileBrowserSidebarSpaceContent(
            configuration: configuration,
            space: space,
            isSelected: isSelected
        )
        .environment(\.colorScheme, spaceColorScheme)
        .blur(radius: isLocked ? BrowserSidebarMetrics.lockedSpaceBlurRadius : 0)
        .redacted(reason: isLocked ? .placeholder : [])
        .allowsHitTesting(!isLocked)
        .accessibilityHidden(isLocked)
        .overlay {
            if isLocked {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: configuration.context.availableSpaces,
                    accessController: configuration.context.spaceAccess,
                    selectSpace: selectUnlockedSpace,
                    presentation: .contentOverlay
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
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
