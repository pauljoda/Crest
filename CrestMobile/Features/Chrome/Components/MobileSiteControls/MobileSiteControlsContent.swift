import SwiftUI

/// Site Controls as iPhone and iPad show them: a sheet that rises from the
/// bottom edge, half the screen tall and pulled up for the rest, or on an
/// iPad wide enough a popover under the control that opened them.
struct MobileSiteControlsContent: View {
    // MARK: - Types

    /// What Site Controls show of the window's commands and downloads, which
    /// they follow while open.
    private struct WindowState: Equatable {
        let commandFlags: [Bool]
        let newDownloadCount: Int

        init(commands: MobileBrowserCommandContext?, downloadsAccess: MobileDownloadsMenuAccess?) {
            commandFlags =
                commands.map {
                    [
                        $0.hasActivePage, $0.hasSelectedTab, $0.isLoading, $0.showsSite, $0.isPrivateBrowsing,
                        $0.canSaveSelectedTab, $0.canDuplicateSelectedTab, $0.canArchiveSelectedTab,
                        $0.canToggleReaderMode, $0.canToggleTranslationToolbar, $0.isTranslationToolbarVisible,
                        $0.hasBlockedElements,
                    ]
                } ?? []
            newDownloadCount = downloadsAccess?.newItemCount ?? 0
        }
    }

    // MARK: - Variables

    let usesSheet: Bool
    /// The window's commands and downloads as the window gives them now.
    private let commands: MobileBrowserCommandContext?
    private let downloadsAccess: MobileDownloadsMenuAccess?

    @State private var model: SiteControlsModel
    /// The model's platform, kept with it, so what waits for Site Controls to
    /// go away waits on the one the model runs.
    @State private var platform: MobileSiteControls

    // MARK: - Actions - Drawing

    var body: some View {
        SiteControlsView(model: model)
            .environment(\.siteControlsMetrics, usesSheet ? .sheet : .popover)
            .padding(.top, usesSheet ? CrestSpacing.small : 0)
            .presentationDetents(usesSheet ? [.medium, .large] : [.large])
            .presentationDragIndicator(usesSheet ? .visible : .hidden)
            .presentationCompactAdaptation(.sheet)
            .accessibilityIdentifier("browser-site-controls-popover")
            // What waits for Site Controls to go away, such as the share
            // sheet, runs once they are gone.
            .onDisappear { platform.didDismiss() }
            // The window gives its commands and downloads anew as it changes;
            // Site Controls follow them while open.
            .onChange(of: WindowState(commands: commands, downloadsAccess: downloadsAccess)) {
                platform.follow(commands: commands, downloadsAccess: downloadsAccess)
            }
            .onChange(of: model.page.sitePermissionRequests.current?.id) {
                model.remembersPermission = true
                if model.page.sitePermissionRequests.current != nil { model.showRoot() }
            }
    }

    init(
        browser: BrowserStore, pages: MobileSelectedPageActionPort, page: MobileBrowserPage,
        commands: MobileBrowserCommandContext?, source: CGRect?, hideToolbar: (() -> Void)?,
        downloadsAccess: MobileDownloadsMenuAccess?, usesSheet: Bool, dismiss: @escaping () -> Void
    ) {
        let platform = MobileSiteControls(
            browser: browser, pages: pages, page: page, commands: commands, source: source, hideToolbar: hideToolbar,
            downloadsAccess: downloadsAccess, dismiss: { dismiss() })
        let model = SiteControlsModel(platform: platform)
        platform.openSiteControlsPage = { [weak model] in model?.open($0) }
        self.usesSheet = usesSheet
        self.commands = commands
        self.downloadsAccess = downloadsAccess
        _platform = State(initialValue: platform)
        _model = State(initialValue: model)
    }
}
