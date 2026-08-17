import SwiftUI

struct BrowserQuickWindowScene: View {
    @Binding var request: BrowserQuickWindowRequest?
    let browser: BrowserStore
    let pages: BrowserPagePool?
    let spaceAccess: BrowserSpaceAccessController
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let preferences: BrowserTransientBrowsingPreferences
    let previewModel: BrowserQuickWindowModel?

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @State private var isRoutingExternalURL = false

    init(
        request: Binding<BrowserQuickWindowRequest?>,
        browser: BrowserStore,
        pages: BrowserPagePool,
        spaceAccess: BrowserSpaceAccessController,
        pagePoolRegistry: BrowserPagePoolRegistry,
        preferences: BrowserTransientBrowsingPreferences = .production
    ) {
        _request = request
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.pagePoolRegistry = pagePoolRegistry
        self.preferences = preferences
        previewModel = nil
    }

    init(
        previewing request: Binding<BrowserQuickWindowRequest?>,
        model: BrowserQuickWindowModel,
        spaceAccess: BrowserSpaceAccessController
    ) {
        _request = request
        browser = model.browser
        pages = nil
        self.spaceAccess = spaceAccess
        pagePoolRegistry = nil
        preferences = .isolated
        previewModel = model
    }

    var body: some View {
        BrowserQuickWindowSceneContent(
            request: request,
            context: resolvedContext,
            isRoutingExternalURL: isRoutingExternalURL,
            spaceAccess: spaceAccess,
            pagePoolRegistry: pagePoolRegistry,
            preferences: preferences,
            previewModel: previewModel,
            requestLifecycle: requestLifecycle,
            openBrowserWindow: openBrowserWindow
        )
        .onOpenURL { url in
            Task { await routeExternalURL(url) }
        }
    }

    private var contextResolver: BrowserQuickWindowContextResolver? {
        guard let pages, let pagePoolRegistry else { return nil }
        return BrowserQuickWindowContextResolver(
            browser: browser,
            pages: pages,
            pagePoolRegistry: pagePoolRegistry
        )
    }

    private var resolvedContext: BrowserQuickWindowBrowsingContext? {
        guard let request, let contextResolver else { return nil }
        return contextResolver.context(for: request)
    }

    private var requestLifecycle: BrowserQuickWindowRequestLifecycle {
        let requestBinding = $request
        return BrowserQuickWindowRequestLifecycle(
            isCurrent: { expected in
                requestBinding.wrappedValue?
                    .hasSamePresentationIdentity(as: expected) == true
            },
            replace: { expected, revised in
                guard
                    requestBinding.wrappedValue?
                        .hasSamePresentationIdentity(as: expected) == true
                else { return false }
                requestBinding.wrappedValue = revised
                return true
            }
        )
    }

    private func routeExternalURL(_ url: URL) async {
        guard BrowserExternalURLPolicy.accepts(url) else { return }
        isRoutingExternalURL = true
        defer { isRoutingExternalURL = false }
        let targetWindowID = request?.targetWindowID
        guard
            let initialContext = contextResolver?.context(
                targetWindowID: targetWindowID
            )
        else { return }
        let decision = BrowserLinkPreferenceStore.shared.routingDecision(
            for: url,
            in: initialContext.browser.session,
            unavailableSpaceIDs: initialContext.browser.deletingSpaceIDs
        )
        guard
            let space = initialContext.browser.session.space(
                id: decision.spaceID
            )
        else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard await spaceAccess.unlock(space),
            let context = contextResolver?.context(
                targetWindowID: targetWindowID
            ),
            context.browser.space(matching: assignment) != nil
        else {
            return
        }

        switch decision {
        case .quickWindow:
            request = BrowserQuickWindowRequest(
                url: url,
                spaceAssignment: assignment,
                targetWindowID: targetWindowID
            )
        case .space:
            guard
                context.browser.openNewTab(
                    url: url,
                    matching: assignment
                ) != nil
            else { return }
            context.pages.select(session: context.browser.session)
            context.pages.load(url)
            openBrowserWindow()
            dismissWindow()
        }
    }

    private func openBrowserWindow() {
        openWindow(id: BrowserSceneID.browser.rawValue)
    }
}
