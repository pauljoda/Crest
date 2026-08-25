import SwiftUI

struct MobileBrowserSidebarBottomChromeLayout<Content: View>: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let content: Content

    init(
        configuration: MobileBrowserSidebarContentConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        switch MobileBrowserSidebarBottomChromePolicy.placement(
            reservesInset: configuration.reservesBottomChromeInset,
            isVisible: configuration.showsBottomSpaceSwitcher
        ) {
        case .hidden:
            content
        case .inlineSafeAreaInset:
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        // A top layer over every Space of every profile: mounted
                        // beside the pager and never keyed to the selected Space,
                        // so a Space switch cannot unmount or recreate the deck.
                        if BrowserSidebarWidgetHostPolicy.shouldRender(
                            sidebarIsPresented:
                                configuration.sidebarIsPresented,
                            isPrivateBrowsing: configuration.context.browser
                                .isPrivateBrowsing
                        ) {
                            BrowserSidebarWidgetHost(
                                capabilities: [
                                    .persistentSidebar,
                                    .mediaSessions,
                                ],
                                activateMediaSession: activateMediaSession,
                                ownerFaviconData: ownerFaviconData
                            )
                        }

                        MobileBrowserSidebarBottomChrome(
                            configuration: configuration
                        )
                    }
                }
        }
    }

    private func ownerFaviconData(
        _ assignment: BrowserTabRuntimeAssignment
    ) -> Data? {
        guard
            let space = configuration.context.browser.session.space(
                id: assignment.spaceID
            ),
            space.profile.id == assignment.profileID,
            let tab = space.tabs.first(where: { $0.id == assignment.tabID })
        else { return nil }
        return tab.displayFaviconData
    }

    private func activateMediaSession(
        _ assignment: BrowserTabRuntimeAssignment
    ) {
        Task { @MainActor in
            guard
                configuration.pages.containsResidentPage(matching: assignment),
                let space = configuration.context.browser.session.space(
                    id: assignment.spaceID
                ),
                space.profile.id == assignment.profileID,
                space.tabs.contains(where: { $0.id == assignment.tabID }),
                await configuration.context.spaceAccess.unlock(space)
            else { return }
            configuration.context.selectSpace(assignment.spaceID)
            configuration.selectTab(assignment.tabID)
        }
    }
}
