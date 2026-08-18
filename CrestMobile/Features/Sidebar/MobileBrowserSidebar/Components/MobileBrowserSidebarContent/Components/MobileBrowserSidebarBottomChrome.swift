import SwiftUI

struct MobileBrowserSidebarBottomChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        ZStack {
            actions

            if configuration.showsSidebarToggle {
                HStack {
                    Button(action: configuration.toggleSidebar) {
                        MobileSpaceUtilityButtonLabel(systemImage: "sidebar.left")
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
        .padding(
            .bottom,
            configuration.mode == .regularSidebar
                && !configuration.sidebarIsDocked
                ? MobileBrowserRootLayout.floatingSidebarBottomChromeInset
                : 0
        )
    }

    @ViewBuilder
    private var actions: some View {
        switch MobileBrowserSidebarBottomChromePolicy.content(
            for: configuration.mode,
            isVisible: isVisible
        ) {
        case .actions:
            if BrowserSidebarAccessPolicy.showsSelectedSpaceActions(
                in: configuration.browser,
                accessController: configuration.spaceAccess
            ) {
                MobileSpaceActions(
                    browser: configuration.browser,
                    pages: configuration.pages,
                    mode: configuration.mode,
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

    private var isVisible: Bool {
        configuration.mode == .regularSidebar
            || configuration.showsBottomSpaceSwitcher
    }

    private var sidebarToggleTitle: LocalizedStringKey {
        if configuration.mode == .compactTabViewer {
            return "Undock Sidebar"
        }
        return configuration.sidebarIsDocked
            ? "Hide Sidebar"
            : "Dock Sidebar"
    }
}
