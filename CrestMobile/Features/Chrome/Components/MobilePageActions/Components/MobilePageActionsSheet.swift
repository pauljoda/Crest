import SwiftUI

/// The page menu of a compact window in search mode, a sheet over the page.
/// It leads with the page's address, read-only until tapped, between Back,
/// Forward, Copy Link and Reload; then the actions used most as tiles, the
/// rest as rows, and blocking for the site last. It opens with the keyboard
/// down, so nothing typed by chance replaces the address.
struct MobilePageActionsSheet: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    var downloadsAccess: MobileDownloadsMenuAccess?
    /// Edits the address in the palette grown out of the bar; nil where the
    /// window offers no palette.
    var editAddress: (() -> Void)?
    let toggleShownTabPinned: () -> Void
    /// Closes the sheet and then runs the action, for one that needs the
    /// page, the keyboard or a sheet of its own.
    let dismissThen: (@escaping () -> Void) -> Void

    var body: some View {
        List {
            Section {
                addressRow
                tiles
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: CrestSpacing.small, leading: 0, bottom: CrestSpacing.small, trailing: 0))

            if let notice = pages.blockedPopupNotice {
                MobileBlockedPopupActions(notice: notice, allow: pages.allowAutomaticPopupsForBlockedSite)
            }

            Section {
                if let page = pages.activePage {
                    translation(for: page)
                }
                pageZoom
                Button(
                    pages.preferredContentModeActionTitle,
                    systemImage: pages.activePage?.isRequestingDesktopSite == true ? "iphone" : "desktopcomputer"
                ) {
                    dismissThen(pages.togglePreferredContentMode)
                }
                if pages.canAddToHomeScreen {
                    Button("Add to Home Screen", systemImage: "plus.app") {
                        dismissThen { pages.addToHomeScreen(from: nil) }
                    }
                }
                if let downloadsAccess {
                    Button(downloadsAccess.rowTitle, systemImage: "arrow.down.circle") {
                        dismissThen(downloadsAccess.open)
                    }
                    .accessibilityLabel("Downloads")
                    .accessibilityValue(downloadsAccess.unreadAccessibilityValue)
                }
            }

            Section {
                siteSettings
                printAndExport
            }

            if let siteSwitch = contentBlocking.siteSwitch {
                Section {
                    Toggle(
                        isOn: Binding {
                            siteSwitch.blocks
                        } set: { _ in
                            switchBlocking()
                        }
                    ) {
                        Label {
                            Text("Block Ads and Trackers")
                            Text(siteSwitch.origin.host)
                        } icon: {
                            Image(systemName: siteSwitch.blocks ? "shield.lefthalf.filled" : "shield.slash")
                        }
                    }
                    .tint(CrestColor.success)
                } footer: {
                    Text("Turning blocking off or on for this site reloads the page.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .tint(.primary)
        .accessibilityIdentifier("page-menu")
    }

    // MARK: - Address

    /// Back, Forward, the address, Copy Link and Reload, the address leading
    /// to editing only when tapped.
    private var addressRow: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            Button(ShortcutCommand.back) { dismissThen(pages.goBack) }
                .disabled(!pages.canGoBack)
            Button(ShortcutCommand.forward) { dismissThen(pages.goForward) }
                .disabled(!pages.canGoForward)
            Button {
                if let editAddress { dismissThen(editAddress) }
            } label: {
                address
            }
            .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.control))
            .layoutPriority(1)
            .disabled(editAddress == nil)
            .accessibilityLabel("Address")
            .accessibilityValue(pages.activeURL?.absoluteString ?? "")
            .accessibilityHint("Edits the address")
            .accessibilityIdentifier("page-menu-address")
            Button(ShortcutCommand.copyPageLink) {
                pages.copyPageLink()
                dismissThen {}
            }
            Button(pages.activePage?.live.isLoading == true ? ShortcutCommand.stopLoading : .reloadPage) {
                dismissThen(pages.reloadOrStop)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle())
        .padding(.horizontal, CrestSpacing.extraSmall)
        .background(.quaternary, in: .capsule)
    }

    /// The page's site in full and its path dimmed, on one line.
    private var address: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            if pages.activeURL?.scheme?.lowercased() == "https" {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            // The site stays whole, shrinking a little if it must; the path
            // gives way first.
            HStack(spacing: 0) {
                Text(host)
                    .fontWeight(.semibold)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Text(path)
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
            }
            .font(.subheadline)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: CrestLayout.minimumHitTarget)
        .padding(.horizontal, CrestSpacing.extraSmall)
    }

    private var host: String {
        pages.activeURL?.host() ?? pages.activeURL?.absoluteString ?? ""
    }

    private var path: String {
        guard let url = pages.activeURL, url.host() != nil,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return "" }
        let path = components.percentEncodedPath == "/" ? "" : components.percentEncodedPath
        return path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
    }

    // MARK: - Tiles

    /// Find, Reader, Pin and Share: what a page is opened for most.
    private var tiles: some View {
        HStack(spacing: CrestSpacing.small) {
            Button(ShortcutCommand.findInPage) { dismissThen(pages.presentFind) }
            Button(pages.readerModeActionTitle, systemImage: pages.readerModeState.actionSymbol) {
                dismissThen(pages.toggleReaderMode)
            }
            .disabled(!pages.readerModeState.canToggle)
            Button(isShownTabPinned ? "Unpin Tab" : "Pin Tab", systemImage: isShownTabPinned ? "pin.slash" : "pin") {
                dismissThen(toggleShownTabPinned)
            }
            if let url = pages.activeURL {
                ShareLink(item: url) {
                    Label(ShortcutCommand.sharePage)
                }
            }
        }
        .labelStyle(MobilePageActionTileLabelStyle())
        .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.card, showsRestingFill: true))
    }

    private var isShownTabPinned: Bool {
        browser.shownTab?.placement == .pinned
    }

    // MARK: - Rows

    private func translation(for page: MobileBrowserPage) -> some View {
        Menu("Translate Page", systemImage: "translate") {
            BrowserTranslationActions(translation: page.translation)
                .crestMenuActionLabelStyle()
            Button("Show Translation Controls", systemImage: "rectangle.topthird.inset.filled") {
                dismissThen(page.translation.present)
            }
        }
        .disabled(page.readerModeState.isActive)
        .task { await page.translation.refreshInstalledLanguages() }
    }

    /// Page Zoom with its own − and +, which keep the sheet up while the page
    /// behind it grows or shrinks. VoiceOver adjusts it as one control.
    private var pageZoom: some View {
        HStack {
            Label("Page Zoom", systemImage: "textformat.size")
            Spacer()
            HStack(spacing: 0) {
                Button(ShortcutCommand.zoomOut, action: pages.zoomOut)
                Button(action: pages.resetZoom) {
                    Text(pages.pageZoomLabel)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
                .buttonStyle(
                    CrestChromeButtonStyle(
                        controlSize: CGSize(width: 60, height: CrestLayout.minimumHitTarget),
                        cornerRadius: CrestRadius.control))
                Button(ShortcutCommand.zoomIn, action: pages.zoomIn)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(CrestChromeButtonStyle(cornerRadius: CrestRadius.control))
            .background(.quaternary, in: .capsule)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page Zoom")
        .accessibilityValue(pages.pageZoomLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: pages.zoomIn()
            case .decrement: pages.zoomOut()
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Actual Size", pages.resetZoom)
    }

    /// The site's permissions and data, and blocking parts of its pages.
    private var siteSettings: some View {
        Menu("Site Settings", systemImage: "gearshape") {
            if let page = pages.activePage {
                MobileSitePermissionsMenu(page: page)
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
            if let page = pages.activePage, page.canPickElementToBlock {
                Button(ShortcutCommand.blockElement) {
                    dismissThen { Task { await page.pickElementToBlock() } }
                }
            }
            if blockedElements.exist {
                Button(ShortcutCommand.showBlockedElements) {
                    let elements = blockedElements
                    dismissThen {
                        Task {
                            await elements.show(
                                refresh: { await pages.reloadContentBlocking() }, reload: { pages.reload() })
                        }
                    }
                }
            }
        }
        .crestMenuActionLabelStyle()
    }

    private var printAndExport: some View {
        Menu("Print & Export", systemImage: "printer") {
            Button(ShortcutCommand.printPage) { dismissThen(pages.printPage) }
            Menu {
                ForEach(MobileBrowserFileExportDestination.all) { destination in
                    Button(destination.title, systemImage: destination.symbol) {
                        dismissThen { pages.exportPDF(to: destination) }
                    }
                }
                .crestMenuActionLabelStyle()
            } label: {
                Label(ShortcutCommand.exportPDF)
            }
            Menu {
                ForEach(MobileBrowserFileExportDestination.all) { destination in
                    Button(destination.title, systemImage: destination.symbol) {
                        dismissThen { pages.exportWebArchive(to: destination) }
                    }
                }
                .crestMenuActionLabelStyle()
            } label: {
                Label(ShortcutCommand.saveWebArchive)
            }
            Button(ShortcutCommand.copyPageLinkAsMarkdown) {
                pages.copyPageLinkAsMarkdown()
            }
        }
        .crestMenuActionLabelStyle()
    }

    // MARK: - Blocking

    private var contentBlocking: MobileContentBlockingAction {
        MobileContentBlockingAction(browser: browser, pages: pages)
    }

    private var blockedElements: BrowserBlockedElements {
        BrowserBlockedElements(core: browser.core, pageURL: pages.activePage?.webView.url)
    }

    /// Turns blocking off or on for the site; the page reloads behind the
    /// sheet, which stays up to show the switch's new state.
    private func switchBlocking() {
        let action = contentBlocking
        Task { await action.perform() }
    }
}
