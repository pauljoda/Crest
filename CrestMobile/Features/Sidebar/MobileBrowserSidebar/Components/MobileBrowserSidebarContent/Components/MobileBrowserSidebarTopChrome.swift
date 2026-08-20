import SwiftUI

struct MobileBrowserSidebarTopChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if configuration.utilityPresentationStyle == .inline {
            BrowserSidebarNavigationControls(
                port: BrowserSidebarNavigationPort(
                    pageActions: selectedPageActions
                ),
                capabilities: configuration.context.capabilities,
                hidesUnavailableForwardControl: true
            ) {
                if let pageActions = selectedPageActions,
                    pageActions.isAvailable
                {
                    MobilePageActionsMenu(
                        browser: configuration.context.browser,
                        pages: pageActions,
                        systemImage: "ellipsis.circle"
                    )
                    .font(.system(size: 17, weight: .medium))
                } else {
                    Button(
                        "Page Actions",
                        systemImage: "ellipsis.circle",
                        action: {}
                    )
                    .disabled(true)
                    .font(.system(size: 17, weight: .medium))
                }
            }

            if let utilitySurface = configuration.context.utilityPresentation
                .surface
            {
                BrowserUtilitySearchToolbar(
                    surface: utilitySurface,
                    searchText: configuration.context.utilitySearchText,
                    filter: configuration.context.utilityFilter,
                    morphNamespace: configuration.compactChromeNamespace,
                    morphID: morphID,
                    clearHistory: confirmClearHistory
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                BrowserSidebarAddressField(
                    configuration: addressConfiguration,
                    fieldContextMenu: {
                        if let pageActions = selectedPageActions,
                            pageActions.isAvailable,
                            !configuration.isAddressEditing.wrappedValue
                        {
                            MobilePageActionsContent(
                                browser: configuration.context.browser,
                                pages: pageActions
                            )
                            .tint(.primary)
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }

        if configuration.showsCompactAddressBar {
            GlassEffectContainer(spacing: 0) {
                MobileCompactNewTabPrompt(
                    namespace: configuration.compactChromeNamespace,
                    geometryID: configuration.context.browser.session
                        .selectedSpaceID,
                    transitionEnded: configuration.compactTransitionEnded,
                    openNewTab: configuration.openNewTab
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    /// `hasResidentPage` stays off: the compact field has no live-site controls
    /// to hand its leading slot, so the glyph there belongs to editing alone.
    private var addressConfiguration: BrowserSidebarAddressFieldConfiguration {
        BrowserSidebarAddressFieldConfiguration(
            text: configuration.address,
            isEditing: configuration.isAddressEditing,
            isSecure: displayedURL?.scheme?.lowercased() == "https",
            progress: selectedPageActions?.activePage?.estimatedProgress ?? 0,
            isLoading: selectedPageActions?.activePage?.isLoading == true,
            hasResidentPage: false,
            capabilities: configuration.context.capabilities,
            activate: configuration.activateAddress,
            submit: configuration.submitAddress,
            morphNamespace: configuration.compactChromeNamespace,
            morphID: morphID
        )
    }

    private var selectedPageActions: MobileSelectedPageActionPort? {
        MobileSelectedPageActionPort(
            browser: configuration.context.browser,
            pages: configuration.pages
        )
    }

    private var displayedURL: URL? {
        selectedPageActions?.activeURL
            ?? configuration.context.browser.selectedTab?.url
    }

    private var morphID: String {
        "crest-address-command-\(configuration.context.browser.session.selectedSpaceID)"
    }

    /// The toolbar sits above the pager, so the Space it clears is the selected
    /// one. The root refuses the request unless that Space is still reachable.
    private func confirmClearHistory() {
        guard let space = configuration.context.browser.selectedSpace else {
            return
        }
        configuration.context.confirmClearHistory(space)
    }
}
