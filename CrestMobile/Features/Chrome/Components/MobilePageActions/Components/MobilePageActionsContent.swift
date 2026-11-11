import SwiftUI

struct MobilePageActionsContent: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    var downloadsAccess: MobileDownloadsMenuAccess? = nil
    var hideToolbar: (() -> Void)? = nil
    /// The frame in the window of the control that opened these actions,
    /// which a sheet they open points at on iPad.
    var source: CGRect? = nil

    var body: some View {
        if let downloadsAccess {
            Button(action: downloadsAccess.open) {
                Label(downloadsAccess.rowTitle, systemImage: "arrow.down.circle")
            }
            .accessibilityLabel("Downloads")
            .accessibilityValue(
                BrowserChromeAccessibility.countValue(
                    downloadsAccess.newItemCount,
                    singular: "new download",
                    plural: "new downloads"
                )
            )
            .accessibilityIdentifier("page-actions-downloads")
        }

        if let notice = pages.blockedPopupNotice {
            MobileBlockedPopupActions(notice: notice, allow: pages.allowAutomaticPopupsForBlockedSite)
        }

        ControlGroup {
            if let url = pages.activeURL {
                ShareLink(item: url) {
                    Label(ShortcutCommand.sharePage)
                }
            }

            Button(ShortcutCommand.copyPageLink) {
                pages.copyPageLink()
            }

            Button(pages.activePage?.live.isLoading == true ? ShortcutCommand.stopLoading : .reloadPage) {
                pages.reloadOrStop()
            }

        }
        .labelStyle(.iconOnly)

        if pages.canAddToHomeScreen {
            Button("Add to Home Screen", systemImage: "plus.app") {
                pages.addToHomeScreen(from: source)
            }
            .accessibilityIdentifier("page-actions-add-to-home-screen")
        }

        Button(
            pages.preferredContentModeActionTitle,
            systemImage: pages.activePage?.isRequestingDesktopSite == true
                ? "iphone"
                : "desktopcomputer"
        ) {
            pages.togglePreferredContentMode()
        }

        Button(
            pages.readerModeActionTitle,
            systemImage: pages.readerModeState.actionSymbol
        ) {
            pages.toggleReaderMode()
        }
        .disabled(!pages.readerModeState.canToggle)

        Button(
            contentBlockingActionTitle,
            systemImage: pages.activePage?.isContentBlockingActive == true
                ? "shield.lefthalf.filled"
                : "shield.slash"
        ) {
            Task { await contentBlockingAction.perform() }
        }
        .disabled(contentBlockingAction.siteSwitch == nil)

        if let page = pages.activePage, page.canPickElementToBlock {
            Button(ShortcutCommand.blockElement) {
                Task { await page.pickElementToBlock() }
            }
        }

        if blockedElements.exist {
            Button(ShortcutCommand.showBlockedElements) {
                let elements = blockedElements
                Task {
                    await elements.show(refresh: { await pages.reloadContentBlocking() }, reload: { pages.reload() })
                }
            }
        }

        if let page = pages.activePage {
            MobileSitePermissionsMenu(page: page)
            Menu("Translate Page", systemImage: "translate") {
                BrowserTranslationActions(translation: page.translation)
                    .crestMenuActionLabelStyle()
                Button("Show Translation Controls", systemImage: "rectangle.topthird.inset.filled") {
                    page.translation.present()
                }
            }
            .disabled(page.readerModeState.isActive)
            .task { await page.translation.refreshInstalledLanguages() }
        }

        if pages.activeURL?.host()?.isEmpty == false {
            Section {
                Button(ShortcutCommand.clearSiteCookies) {
                    Task { await pages.clearSiteData(.siteData) }
                }
                Button(ShortcutCommand.clearSiteCache) {
                    Task { await pages.clearSiteData(.cache) }
                }
            }
        }

        Button(ShortcutCommand.findInPage) {
            pages.presentFind()
        }

        if let hideToolbar {
            Button("Hide Toolbar", systemImage: "chevron.down") {
                hideToolbar()
            }
        }

        Section("Page Zoom") {
            Button(ShortcutCommand.zoomOut) {
                pages.zoomOut()
            }

            Button("Actual Size (\(pages.pageZoomLabel))", systemImage: ShortcutCommand.actualSize.symbol) {
                pages.resetZoom()
            }

            Button(ShortcutCommand.zoomIn) {
                pages.zoomIn()
            }
        }

        Section {
            Button(ShortcutCommand.copyPageLinkAsMarkdown) {
                pages.copyPageLinkAsMarkdown()
            }

            Menu("Share & Export…", systemImage: "square.and.arrow.up") {
                Group {
                    if let url = pages.activeURL {
                        ShareLink(item: url) {
                            Label(ShortcutCommand.sharePage)
                        }
                    }

                    Button(ShortcutCommand.printPage) {
                        pages.printPage()
                    }

                    Menu {
                        ForEach(MobileBrowserFileExportDestination.all) {
                            destination in
                            Button(
                                destination.title,
                                systemImage: destination.symbol
                            ) {
                                pages.exportPDF(to: destination)
                            }
                        }
                        .crestMenuActionLabelStyle()
                    } label: {
                        Label(ShortcutCommand.exportPDF)
                    }

                    Menu {
                        ForEach(MobileBrowserFileExportDestination.all) {
                            destination in
                            Button(
                                destination.title,
                                systemImage: destination.symbol
                            ) {
                                pages.exportWebArchive(to: destination)
                            }
                        }
                        .crestMenuActionLabelStyle()
                    } label: {
                        Label(ShortcutCommand.saveWebArchive)
                    }
                }
                .crestMenuActionLabelStyle()
            }
        }
    }

    private var blockedElements: BrowserBlockedElements {
        BrowserBlockedElements(core: browser.core, pageURL: pages.activePage?.webView.url)
    }

    private var contentBlockingAction: MobileContentBlockingAction {
        MobileContentBlockingAction(browser: browser, pages: pages)
    }

    private var contentBlockingActionTitle: LocalizedStringResource {
        contentBlockingAction.title
    }
}
