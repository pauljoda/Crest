import SwiftUI

struct MobileBrowserSidebarBottomChrome: View {
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    let configuration: MobileBrowserSidebarContentConfiguration

    private var sidebarOnRight: Bool { BrowserDeviceAppearanceStore.shared.sidebarOnRight }

    var body: some View {
        if controlPlacement.movesControlsToToolbar {
            // The controls are toolbar items, so the chrome holds no room under
            // the tabs for them.
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
                .toolbar { toolbarItems }
        } else {
            capsule
        }
    }

    /// The controls as items in the side toolbar's bottom group, or along the
    /// top bar after the page's.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if configuration.showsSidebarToggle {
            ToolbarItem(placement: controlPlacement.spaceControlsPlacement) { sidebarToggle }
                .collapsing(at: .navigation)
        }
        if showsNewTab {
            ToolbarItem(placement: controlPlacement.spaceControlsPlacement) { newTabButton }
                .collapsing(at: .newTab)
        }
        if showsSpaceActions {
            MobileSpaceActionButtons(
                browser: configuration.context.browser,
                pages: configuration.pages,
                utilityPresentationStyle: configuration.utilityPresentationStyle,
                configuration: configuration.spaceActionsConfiguration
            )
            .toolbarItems(placement: controlPlacement.spaceControlsPlacement)
        }
    }

    private var capsule: some View {
        controls
            .frame(height: 60)
            .modifier(
                SpaceForegroundBlend(
                    spaces: configuration.context.availableSpaces,
                    selectedSpaceID: configuration.context.browser.shownSpace?.id)
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

    private var sidebarToggle: some View {
        Button(action: configuration.toggleSidebar) {
            MobileSpaceUtilityButtonLabel(
                title: sidebarToggleTitle, systemImage: sidebarOnRight ? "sidebar.right" : "sidebar.left")
        }
        .help(sidebarToggleTitle)
        .accessibilityLabel(sidebarToggleTitle)
        .accessibilityIdentifier("browser-sidebar-toggle")
    }

    /// New Tab rides with the sidebar toggle, so a new tab is always a tap
    /// away whether or not the toggle is on.
    private var newTabButton: some View {
        Button(action: configuration.openNewTab) {
            MobileSpaceUtilityButtonLabel(title: "New Tab", systemImage: "plus")
        }
        .foregroundStyle(.primary)
        .help("New Tab")
        .accessibilityLabel("New Tab")
        .accessibilityIdentifier("browser-sidebar-new-tab")
    }

    /// Shown with the Space's own controls: a locked Space takes no new tab.
    private var showsNewTab: Bool {
        !holdsReservedSpace && showsSpaceActions
    }

    private var showsSpaceActions: Bool {
        configuration.context.browser.showsSelectedSpaceActions(
            accessController: configuration.context.spaceAccess)
    }

    /// The sidebar toggle and New Tab in a capsule of their own at the
    /// leading edge, and the Space's controls at the trailing edge. A sidebar
    /// too narrow for both keeps every control in one capsule, toggle and New
    /// Tab first, which narrows its buttons as the sidebar narrows further.
    @ViewBuilder
    private var controls: some View {
        if showsNewTab {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    leadingControls
                    Spacer(minLength: 0)
                    spaceActions { EmptyView() }
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 12)

                HStack(spacing: 0) {
                    spaceActions { leadingButtons }
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
            }
            .transition(.opacity)
        } else {
            HStack(spacing: 0) {
                if configuration.showsSidebarToggle {
                    leadingControls
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .accessibilityHidden(!configuration.showsSidebarToggle)
        }
    }

    private var leadingControls: some View {
        HStack(spacing: 0) {
            leadingButtons
        }
        .buttonStyle(.plain)
        .controlSize(.large)
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var leadingButtons: some View {
        if configuration.showsSidebarToggle {
            sidebarToggle
        }
        if showsNewTab {
            newTabButton
        }
    }

    private func spaceActions(@ViewBuilder leading: () -> some View) -> some View {
        MobileSpaceActions(
            browser: configuration.context.browser,
            pages: configuration.pages,
            utilityPresentationStyle: configuration.utilityPresentationStyle,
            configuration: configuration.spaceActionsConfiguration,
            leading: leading
        )
    }

    /// Whether the chrome only holds its reserved inset open, its controls
    /// being off screen.
    private var holdsReservedSpace: Bool {
        configuration.reservesBottomChromeInset && !configuration.showsBottomSpaceSwitcher
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
