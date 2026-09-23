import AppKit
import SwiftUI

struct BrowserMacWindowScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    let model: BrowserMacWindowModel
    let coordinator: BrowserMacWindowCoordinator
    @State private var registered = false
    @State private var closed = false
    var id: BrowserWindowID { model.id }
    var browser: BrowserStore { model.browser }
    var pages: BrowserPagePool { model.pages }
    var chrome: BrowserChromeState { model.chrome }
    var transientBrowsing: BrowserTransientBrowsingCoordinator { model.transientBrowsing }
    var windowState: BrowserWindowStateStore { model.windowState }
    private let pagePoolRegistry: BrowserPagePoolRegistry
    private let spaceAccess: BrowserSpaceAccessController
    private let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    private let startupBehavior: BrowserStartupBehavior
    private let shortcuts: BrowserShortcutStore?
    private let sidebarWidgets: BrowserSidebarWidgetRuntime
    private let softwareUpdates: BrowserSoftwareUpdateService

    init(
        model: BrowserMacWindowModel,
        coordinator: BrowserMacWindowCoordinator,
        pagePoolRegistry: BrowserPagePoolRegistry,
        spaceAccess: BrowserSpaceAccessController,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState,
        startupBehavior: BrowserStartupBehavior,
        shortcuts: BrowserShortcutStore? = nil,
        sidebarWidgets: BrowserSidebarWidgetRuntime,
        softwareUpdates: BrowserSoftwareUpdateService
    ) {
        self.model = model
        self.coordinator = coordinator
        self.pagePoolRegistry = pagePoolRegistry
        self.spaceAccess = spaceAccess
        self.spaceSettingsPresentation = spaceSettingsPresentation
        self.startupBehavior = startupBehavior
        self.shortcuts = shortcuts
        self.sidebarWidgets = sidebarWidgets
        self.softwareUpdates = softwareUpdates
    }

    var body: some View {
        BrowserRootView(
            browser: browser,
            pages: pages,
            chrome: chrome,
            transientBrowsing: transientBrowsing,
            spaceAccess: spaceAccess,
            windowState: windowState,
            spaceSettingsPresentation: model.spaceSettingsPresentation,
            startupBehavior: startupBehavior,
            shortcuts: shortcuts
        )
        .modifier(BrowserChromeAppearancePersistence())
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
        .environment(
            \.browserApplicationIcon,
            Image(nsImage: NSApplication.shared.applicationIconImage)
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
        .environment(\.browserPagePresentationWindowID, id)
        .environment(
            \.browserSidebarWindowDrop,
            BrowserSidebarWindowDrop(
                perform: handleWindowDrop,
                didMeasureRow: { coordinator.didMeasureRow($0, in: id) })
        )
        .background(
            BrowserMacWindowAttachment(
                prepare: { coordinator.preparePresentation($0, for: id) },
                attach: { window in
                    guard coordinator.attach(window, to: id) else { return }
                    activateWindow()
                    pages.setWindowFocused(window.isKeyWindow)
                },
                focusChanged: { focused in
                    pages.setWindowFocused(focused)
                },
                close: closeWindowRuntime)
        )
        .onAppear(perform: activateWindow)
        .onChange(of: coordinator.browser.sessionRevision) {
            coordinator.reconcileTemporaryWorkspaces()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            spaceAccess.lockAllForInactiveScene()
        }
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
        .onChange(of: browser.selection) {
            windowState.captureSelection(of: browser)
        }
        .onChange(of: chrome.columnVisibility, initial: true) { _, visibility in
            windowState.captureSidebar(
                isPresented: visibility != .detailOnly
            )
        }
        .onChange(of: spaceSettingsPresentation.revision) {
            guard model.window?.isKeyWindow == true,
                let assignment = spaceSettingsPresentation.requestedAssignment,
                browser.space(matching: assignment) != nil
            else { return }
            model.spaceSettingsPresentation.present(
                spaceSettingsPresentation.requestedDestination, assignment: assignment)
            browser.selectSpace(assignment.spaceID)
            browser.openSettings()
            pages.select(session: browser.presented)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                activateWindow()
            } else {
                sidebarWidgets.suspendHost(id: id)
                flushPendingPersistence()
            }
        }
    }

    private func activateWindow() {
        softwareUpdates.applicationDidBecomeActive()
        sidebarWidgets.activateHost(
            id: id,
            capabilities: [
                .persistentSidebar,
                .mediaSessions,
                .directSoftwareUpdates,
            ]
        )
        pagePoolRegistry.register(
            pages,
            browser: browser,
            for: id
        )
    }

    private func closeWindowRuntime() {
        guard !closed else { return }
        closed = true
        (browser.interactionObserver as? BrowserSidebarInteractionState)?.cancel()
        sidebarWidgets.removeHost(id: id)
        pagePoolRegistry.unregister(pages, for: id)
        flushPendingPersistence()
        coordinator.closeWindow(id)
    }

    private func handleWindowDrop(_ lift: BrowserSidebarFloatingLift) -> Bool {
        let event = NSApp.currentEvent
        let point =
            event.flatMap { event in
                event.window?.convertPoint(toScreen: event.locationInWindow)
            } ?? NSEvent.mouseLocation
        return BrowserMacWindowDropAction(
            coordinator: coordinator, sourceWindowID: id,
            open: { request in
                if let host = BrowserMacWindowPresentation.host {
                    host.openWindow(request)
                } else {
                    openWindow(id: BrowserSceneID.blankWindow.rawValue, value: request)
                }
            }
        ).perform(lift.item, at: point, grabFraction: lift.anchorFraction)
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
