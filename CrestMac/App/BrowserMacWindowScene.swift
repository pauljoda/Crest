import SwiftUI

struct BrowserMacWindowScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    let id: BrowserWindowID
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let windowState: BrowserWindowStateStore
    private let extensionControllerPool: BrowserExtensionControllerPool
    private let pagePoolRegistry: BrowserPagePoolRegistry
    private let spaceAccess: BrowserSpaceAccessController
    private let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    private let startupBehavior: BrowserStartupBehavior
    private let shortcuts: BrowserShortcutStore?

    init(
        id: BrowserWindowID,
        browser: BrowserStore,
        pages: BrowserPagePool,
        chrome: BrowserChromeState,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        windowState: BrowserWindowStateStore,
        extensionControllerPool: BrowserExtensionControllerPool,
        pagePoolRegistry: BrowserPagePoolRegistry,
        spaceAccess: BrowserSpaceAccessController,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState,
        startupBehavior: BrowserStartupBehavior,
        shortcuts: BrowserShortcutStore? = nil
    ) {
        self.id = id
        self.browser = browser
        self.pages = pages
        self.chrome = chrome
        self.transientBrowsing = transientBrowsing
        self.windowState = windowState
        self.extensionControllerPool = extensionControllerPool
        self.pagePoolRegistry = pagePoolRegistry
        self.spaceAccess = spaceAccess
        self.spaceSettingsPresentation = spaceSettingsPresentation
        self.startupBehavior = startupBehavior
        self.shortcuts = shortcuts
    }

    var body: some View {
        BrowserRootView(
            browser: browser,
            pages: pages,
            chrome: chrome,
            transientBrowsing: transientBrowsing,
            spaceAccess: spaceAccess,
            windowState: windowState,
            spaceSettingsPresentation: spaceSettingsPresentation,
            startupBehavior: startupBehavior,
            shortcuts: shortcuts
        )
        .frame(
            minWidth: BrowserMainWindowSizingPolicy.minimumContentSize.width,
            idealWidth: BrowserMainWindowSizingPolicy.idealContentSize.width,
            maxWidth: .infinity,
            minHeight: BrowserMainWindowSizingPolicy.minimumContentSize.height,
            idealHeight: BrowserMainWindowSizingPolicy.idealContentSize.height,
            maxHeight: .infinity
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserWindowAccessibilityID.scene(id)
        )
        .modifier(
            BrowserExternalLinkHandler(
                browser: browser,
                pages: pages,
                chrome: chrome,
                spaceAccess: spaceAccess,
                targetWindowID: id
            )
        )
        .onAppear(perform: activateWindow)
        .onDisappear(perform: closeWindowRuntime)
        .task {
            await BrowserDeferredWebsiteDataStoreCleanup.cleanupPendingStores()
        }
        // Retention cleanup follows the scene: it sweeps as soon as this window becomes
        // active and then keeps sweeping on a low-frequency tick, and SwiftUI
        // cancels the loop whenever the phase changes so an inactive window stops
        // sweeping. Windows share one session, which collapses overlapping sweeps.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await browser.sweepExpiredBrowsingDataWhileSceneIsActive {
                pages.downloadCenter.sweepExpiredRecords(using: browser.session)
            }
        }
        .onChange(
            of: BrowserWindowState(
                id: id,
                restoring: browser.session
            )
        ) {
            windowState.captureSelection(from: browser.session)
        }
        .onChange(of: chrome.columnVisibility, initial: true) { _, visibility in
            windowState.captureSidebar(
                isPresented: visibility != .detailOnly
            )
        }
        .onChange(of: spaceSettingsPresentation.revision) {
            openWindow(id: BrowserSceneID.settings.rawValue)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                activateWindow()
            } else {
                if phase == .inactive {
                    spaceAccess.lockAllForInactiveScene()
                } else {
                    spaceAccess.lockAll()
                }
                flushPendingPersistence()
            }
        }
    }

    private func activateWindow() {
        pagePoolRegistry.register(
            pages,
            browser: browser,
            for: id
        )
        extensionControllerPool.connect(
            browser: browser,
            pageProvider: pages
        )
        extensionControllerPool.reconcileExtensionState(in: browser.session)
    }

    private func closeWindowRuntime() {
        pagePoolRegistry.unregister(pages, for: id)
        flushPendingPersistence()
    }

    private func flushPendingPersistence() {
        // Reading each resident page's WebKit session state has to happen while
        // the pages are still resident, so it is captured here rather than inside
        // the detached flush.
        pages.archiveResidentTabStates()
        Task {
            await browser.flushPendingSyncPersistence()
            await windowState.flushPendingPersistence()
            await pages.flushPendingTabStateWrites()
        }
    }
}
