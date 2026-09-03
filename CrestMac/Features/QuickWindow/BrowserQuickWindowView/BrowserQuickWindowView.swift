import SwiftUI

struct BrowserQuickWindowView: View {
    let spaceAccess: BrowserSpaceAccessController
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let openBrowserWindow: () -> Void
    private let request: BrowserQuickWindowRequest?

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model: BrowserQuickWindowModel

    init(
        request: BrowserQuickWindowRequest,
        browser: BrowserStore,
        pages: BrowserPagePool,
        pagePoolRegistry: BrowserPagePoolRegistry?,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        requestLifecycle: BrowserQuickWindowRequestLifecycle,
        openBrowserWindow: @escaping () -> Void = {},
        supportsLivePagePromotion: Bool = false,
        preferences: BrowserTransientBrowsingPreferences = .production
    ) {
        self.request = request
        self.spaceAccess = spaceAccess
        self.pagePoolRegistry = pagePoolRegistry
        self.openBrowserWindow = openBrowserWindow
        _model = State(
            initialValue: BrowserQuickWindowModel(
                request: request,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                supportsLivePagePromotion: supportsLivePagePromotion,
                preferences: preferences,
                requestLifecycle: requestLifecycle
            )
        )
    }

    init(
        model: BrowserQuickWindowModel,
        spaceAccess: BrowserSpaceAccessController,
        openBrowserWindow: @escaping () -> Void = {}
    ) {
        request = nil
        self.spaceAccess = spaceAccess
        pagePoolRegistry = nil
        self.openBrowserWindow = openBrowserWindow
        _model = State(initialValue: model)
    }

    var body: some View {
        BrowserQuickWindowWindowSurface(
            model: model,
            spaceAccess: spaceAccess,
            pagePoolRegistry: pagePoolRegistry,
            dismiss: dismissQuickWindow,
            openBrowserWindow: openBrowserWindow
        )
        .navigationTitle(Text(verbatim: model.windowTitle(for: request ?? model.presentedRequest)))
    }

    private func dismissQuickWindow() {
        dismissWindow(
            id: BrowserSceneID.quickWindow.rawValue,
            value: model.presentedRequest
        )
    }
}

#Preview("Quick Window") {
    BrowserQuickWindowView(
        model: BrowserQuickWindowPreviewFixture.makeModel(),
        spaceAccess: BrowserQuickWindowPreviewFixture.makeAccessController()
    )
    .environment(BrowserWindowTransparencyPreviewFixture.makeStore())
    .frame(
        width: BrowserQuickWindowLayout.defaultWidth,
        height: BrowserQuickWindowLayout.defaultHeight
    )
}
