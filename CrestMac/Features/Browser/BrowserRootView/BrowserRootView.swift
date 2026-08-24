import SwiftUI

struct BrowserRootView: View {
    private let transientBrowsing: BrowserTransientBrowsingCoordinator
    private let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    private let shortcuts: BrowserShortcutStore?
    private let persistSidebarWidth: (Double) -> Void

    @Environment(BrowserWindowTransparencyStore.self)
    private var windowTransparency
    @State private var model: BrowserRootModel
    @State private var storedSidebarWidth: Double
    @Namespace private var commandSurfaceNamespace
    @Namespace private var tabPromotionNamespace

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        chrome: BrowserChromeState,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        windowState: BrowserWindowStateStore? = nil,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState =
            BrowserSpaceSettingsPresentationState(),
        startupBehavior: BrowserStartupBehavior = .showStartPage,
        shortcuts: BrowserShortcutStore? = nil,
        initialSidebarWidth: Double? = nil,
        persistSidebarWidth: @escaping (Double) -> Void =
            BrowserRootSidebarWidthPersistence.write
    ) {
        self.transientBrowsing = transientBrowsing
        self.spaceSettingsPresentation = spaceSettingsPresentation
        self.shortcuts = shortcuts
        self.persistSidebarWidth = persistSidebarWidth
        let fallbackWidth =
            initialSidebarWidth.map { CGFloat($0) }
            ?? BrowserRootSidebarWidthPersistence.read()
        let resolvedWidth = windowState?.sidebarWidth ?? Double(fallbackWidth)
        _storedSidebarWidth = State(initialValue: resolvedWidth)
        _model = State(
            initialValue: BrowserRootModel(
                browser: browser,
                pages: pages,
                chrome: chrome,
                spaceAccess: spaceAccess,
                windowState: windowState,
                startupBehavior: startupBehavior,
                persistedSidebarWidth:
                    CGFloat(resolvedWidth)
            )
        )
    }

    var body: some View {
        BrowserRootShell(
            model: model,
            transientBrowsing: transientBrowsing,
            spaceSettingsPresentation: spaceSettingsPresentation,
            shortcuts: shortcuts,
            storedSidebarWidth: $storedSidebarWidth,
            windowTransparencyIsEnabled: windowTransparency.isEnabled,
            windowTransparencyStrength: windowTransparency.strength,
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace
        )
        .modifier(
            BrowserRootLifecycleModifier(
                model: model,
                storedSidebarWidth: $storedSidebarWidth,
                persistSidebarWidth: persistSidebarWidth
            )
        )
    }
}

#Preview("Browser Root — Docked") {
    let browser = BrowserRootPreviewFixture.makeBrowser()
    BrowserRootView(
        browser: browser,
        pages: BrowserPagePool(),
        chrome: BrowserRootPreviewFixture.makeChrome(state: .docked),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        windowState: BrowserRootPreviewFixture.makeWindowState(
            session: browser.session
        ),
        initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
        persistSidebarWidth: { _ in }
    )
    .environment(BrowserWindowTransparencyPreviewFixture.makeStore())
    .frame(width: 1_120, height: 720)
}

#Preview("Browser Root — Collapsed") {
    let browser = BrowserRootPreviewFixture.makeBrowser()
    BrowserRootView(
        browser: browser,
        pages: BrowserPagePool(),
        chrome: BrowserRootPreviewFixture.makeChrome(state: .collapsed),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        windowState: BrowserRootPreviewFixture.makeWindowState(
            session: browser.session
        ),
        initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
        persistSidebarWidth: { _ in }
    )
    .environment(BrowserWindowTransparencyPreviewFixture.makeStore())
    .frame(width: 1_120, height: 720)
}

#Preview("Browser Root — Command Palette") {
    let browser = BrowserRootPreviewFixture.makeBrowser()
    BrowserRootView(
        browser: browser,
        pages: BrowserPagePool(),
        chrome: BrowserRootPreviewFixture.makeChrome(state: .commandPalette),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        windowState: BrowserRootPreviewFixture.makeWindowState(
            session: browser.session
        ),
        initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
        persistSidebarWidth: { _ in }
    )
    .environment(BrowserWindowTransparencyPreviewFixture.makeStore())
    .frame(width: 1_120, height: 720)
}
