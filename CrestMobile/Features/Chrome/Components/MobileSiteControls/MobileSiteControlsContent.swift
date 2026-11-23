import SwiftUI

/// Site Controls as iPhone and iPad show them: a sheet that rises from the
/// bottom edge, half the screen tall and pulled up for the rest, or on an
/// iPad wide enough a popover under the control that opened them.
struct MobileSiteControlsContent: View {
    let usesSheet: Bool

    @State private var model: SiteControlsModel
    /// The model's platform, kept with it, so what waits for Site Controls to
    /// go away waits on the one the model runs.
    @State private var platform: MobileSiteControls

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
        _platform = State(initialValue: platform)
        _model = State(initialValue: model)
    }
}
