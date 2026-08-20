import SwiftUI

struct MobileBrowserSidebarTopChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if configuration.mode == .regularSidebar {
            BrowserSidebarNavigationControls(
                port: BrowserSidebarNavigationPort(
                    pageActions: selectedPageActions
                ),
                capabilities: capabilities,
                hidesUnavailableForwardControl: true
            ) {
                if let pageActions = selectedPageActions,
                    pageActions.isAvailable
                {
                    MobilePageActionsMenu(
                        browser: configuration.browser,
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
                BrowserSidebarAddressField(
                    configuration: addressConfiguration,
                    fieldContextMenu: {
                        if let pageActions = selectedPageActions,
                            pageActions.isAvailable,
                            !configuration.isAddressEditing.wrappedValue
                        {
                            MobilePageActionsContent(
                                browser: configuration.browser,
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
            capabilities: capabilities,
            activate: configuration.activateAddress,
            submit: configuration.submitAddress,
            morphNamespace: configuration.compactChromeNamespace,
            morphID: morphID
        )
    }

    /// What this shell can do, until the shell itself hands it down: a finger
    /// is the primary input and a trackpad may still be attached.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(
            supportsHover: true,
            supportsTouch: true
        )
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
