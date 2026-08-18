import SwiftUI

struct MobileBrowserSidebarTopChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if configuration.mode == .regularSidebar {
            MobileSidebarNavigationControls(
                browser: configuration.browser,
                pageActions: selectedPageActions
            )

            if let utilitySurface = configuration.utilityPresentation.surface {
                BrowserUtilitySearchToolbar(
                    surface: utilitySurface,
                    searchText: configuration.utilitySearchText,
                    filter: configuration.utilityFilter,
                    morphNamespace: configuration.compactChromeNamespace,
                    morphID: morphID,
                    clearHistory: configuration.confirmClearHistory
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                MobileSidebarAddressField(
                    browser: configuration.browser,
                    pageActions: selectedPageActions,
                    text: configuration.address,
                    isEditing: configuration.isAddressEditing,
                    isSecure: displayedURL?.scheme?.lowercased() == "https",
                    progress: selectedPageActions?.activePage?.estimatedProgress ?? 0,
                    isLoading: selectedPageActions?.activePage?.isLoading == true,
                    activate: configuration.activateAddress,
                    submit: configuration.submitAddress,
                    morphNamespace: configuration.compactChromeNamespace,
                    morphID: morphID
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }

        if configuration.mode == .compactTabViewer,
            configuration.showsCompactAddressBar
        {
            GlassEffectContainer(spacing: 0) {
                MobileCompactNewTabPrompt(
                    namespace: configuration.compactChromeNamespace,
                    geometryID: configuration.browser.session.selectedSpaceID,
                    transitionEnded: configuration.compactTransitionEnded,
                    openNewTab: configuration.openNewTab
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private var selectedPageActions: MobileSelectedPageActionPort? {
        MobileSelectedPageActionPort(
            browser: configuration.browser,
            pages: configuration.pages
        )
    }

    private var displayedURL: URL? {
        selectedPageActions?.activeURL ?? configuration.browser.selectedTab?.url
    }

    private var morphID: String {
        "crest-address-command-\(configuration.browser.session.selectedSpaceID)"
    }
}
