import SwiftUI

struct MobileBrowserSidebarBottomChrome: View {
    @Environment(\.browserChromeAppearance) private var appearance
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        ZStack {
            actions

            if configuration.showsSidebarToggle {
                HStack {
                    Button(action: configuration.toggleSidebar) {
                        MobileSpaceUtilityButtonLabel(
                            systemImage: appearance.sidebarOnRight ? "sidebar.right" : "sidebar.left")
                    }
                    .buttonStyle(.plain)
                    .controlSize(.large)
                    .padding(4)
                    .glassEffect(.regular, in: .capsule)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(
                        sidebarToggleTitle
                    )
                    .accessibilityLabel(
                        sidebarToggleTitle
                    )
                    .accessibilityIdentifier("browser-sidebar-toggle")

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 60)
            }
        }
        .modifier(
            SpaceForegroundBlend(
                spaces: configuration.context.availableSpaces,
                selectedSpaceID: configuration.context.browser.selectedSpace?.id)
        )
        .padding(
            .bottom,
            configuration.sidebarIsDocked
                ? configuration.reservesBottomChromeInset
                    ? 0
                    : BrowserChromeLayout.pageFrameInset
                : MobileBrowserRootLayout.floatingSidebarBottomChromeInset
        )
    }

    @ViewBuilder
    private var actions: some View {
        switch MobileBrowserSidebarBottomChromePolicy.content(
            reservesInset: configuration.reservesBottomChromeInset,
            isVisible: configuration.showsBottomSpaceSwitcher
        ) {
        case .actions:
            if BrowserSidebarAccessPolicy.showsSelectedSpaceActions(
                in: configuration.context.browser,
                accessController: configuration.context.spaceAccess
            ) {
                MobileSpaceActions(
                    browser: configuration.context.browser,
                    pages: configuration.pages,
                    utilityPresentationStyle:
                        configuration.utilityPresentationStyle,
                    configuration: configuration.spaceActionsConfiguration
                )
                .transition(.opacity)
            } else {
                reservedSpace
            }
        case .reservedSpace:
            reservedSpace
        }
    }

    private var reservedSpace: some View {
        Color.clear
            .frame(height: 60)
            .accessibilityHidden(true)
    }

    private var sidebarToggleTitle: LocalizedStringKey {
        if configuration.sidebarToggleUndocks {
            return "Undock Sidebar"
        }
        return configuration.sidebarIsDocked
            ? "Hide Sidebar"
            : "Dock Sidebar"
    }
}
