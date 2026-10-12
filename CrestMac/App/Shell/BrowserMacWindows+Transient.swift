import AppKit
import SwiftUI

extension BrowserMacWindows {
    // MARK: - Types

    /// A Quick Window's content, which answers for the window it shows in.
    struct QuickWindow {
        let model: BrowserQuickWindowModel
        let request: QuickRequest
    }

    /// The request a Quick Window shows now, which its content can revise.
    final class QuickRequest {
        var value: BrowserQuickWindowRequest

        init(_ value: BrowserQuickWindowRequest) {
            self.value = value
        }
    }

    /// Keeps a Quick Window's title on what its page shows.
    struct QuickWindowTitle: ViewModifier {
        let model: BrowserQuickWindowModel
        let request: QuickRequest
        weak var window: NSWindow?

        func body(content: Content) -> some View {
            content.onChange(of: model.windowTitle(for: request.value), initial: true) { _, title in
                window?.title = title
            }
        }
    }

    // MARK: - Actions - Private window

    func openPrivateWindow() {
        guard !bringForwardOpenWindow(of: .private) else { return }
        let privatePages = application.privatePages
        // A Quick Window the private window's pages open, such as a sign-in
        // popup, finds its page and workspace through the registry.
        application.pagePoolRegistry.register(
            privatePages, browser: application.privateBrowser, for: privatePages.windowID)
        show(
            .private, id: privatePages.windowID, closeGate: application.privateWindowCloseGate,
            content: { _ in application.privateWindowContent },
            closed: { [weak self] controller in self?.privateWindowClosed(controller) })
    }

    /// Closing the private window ends private browsing: its Quick Windows
    /// go with it, and the engine lets go of its profiles.
    private func privateWindowClosed(_ controller: BrowserMacWindowController) {
        forget(controller)
        for (id, quick) in quickWindows where quick.model.browser.isPrivateBrowsing {
            closeQuickWindowWithoutAsking(id)
        }
        let profiles = application.privateBrowser.spaceModels.map(\.profileID)
        application.pagePoolRegistry.unregister(application.privatePages, for: controller.windowID)
        application.closePrivateBrowsingWindow()
        engineHost.windowClosed(controller.windowID, releasingProfiles: profiles)
    }

    // MARK: - Actions - Quick Windows

    func openQuickWindow(_ request: BrowserQuickWindowRequest) {
        if let existing = quickWindows.first(where: { $0.value.request.value == request }),
            let controller = controller(.quick, id: existing.key)
        {
            controller.present(.key)
            return
        }
        let resolver = BrowserQuickWindowContextResolver(
            browser: application.browser, pages: application.pages, pagePoolRegistry: application.pagePoolRegistry)
        guard let context = resolver.context(for: request),
            let space = context.browser.spaceModel(matching: request.assignment),
            !application.spaceAccess.isLocked(space)
        else {
            if let pageID = request.openedPageID {
                DiagnosticLog.popups.notice("No window hosts the Quick Window for popup page \(pageID.uuidString)")
            }
            return
        }
        let current = QuickRequest(request)
        let model = BrowserQuickWindowModel(
            request: request, browser: context.browser, pages: context.pages, spaceAccess: application.spaceAccess,
            supportsLivePagePromotion: context.supportsLivePagePromotion,
            preferences: .production(core: context.browser.core),
            requestLifecycle: BrowserQuickWindowRequestLifecycle(
                isCurrent: { [weak current] in current?.value.hasSamePresentationIdentity(as: $0) == true },
                replace: { [weak current] expected, revised in
                    guard let current, current.value.hasSamePresentationIdentity(as: expected) else { return false }
                    current.value = revised
                    return true
                }))
        quickWindows[request.id] = QuickWindow(model: model, request: current)
        show(
            .quick, id: request.id, closeGate: model.closeGate,
            content: { window in
                BrowserQuickWindowWindowSurface(
                    model: model, spaceAccess: application.spaceAccess, pagePoolRegistry: application.pagePoolRegistry,
                    // The content closes the window only when the window is
                    // done, which a person's close waiting on the page, or a
                    // refused one, never holds back.
                    dismiss: { [weak self] in self?.closeQuickWindowWithoutAsking(request.id) },
                    openBrowserWindow: { [weak self] in
                        guard let self, !application.windowCoordinator.activateExistingWindow(for: context.browser)
                        else { return }
                        open(.normal(sourceWindowID: request.targetWindowID), activation: .key)
                    }
                )
                .modifier(BrowserChromeAppearancePersistence())
                .environment(application.softwareUpdates)
                .modifier(QuickWindowTitle(model: model, request: current, window: window))
            },
            closed: { [weak self] controller in self?.quickWindowClosed(controller) })
    }

    /// The Quick Window named `id`, while it is open.
    func quickWindow(_ id: UUID) -> NSWindow? {
        controller(.quick, id: id)?.window
    }

    /// Closes the Quick Window named `id` without asking its page: what it
    /// was open for is over.
    func closeQuickWindowWithoutAsking(_ id: UUID) {
        controller(.quick, id: id)?.window.closeAfterApproval()
    }

    /// Closes every Quick Window without asking, as a quit the core allowed
    /// archives them.
    func closeQuickWindowsWithoutAsking() {
        for id in Array(quickWindows.keys) { closeQuickWindowWithoutAsking(id) }
    }

    private func quickWindowClosed(_ controller: BrowserMacWindowController) {
        forget(controller)
        quickWindows.removeValue(forKey: controller.windowID)?.model.releaseForDismissal()
        engineHost.windowClosed(controller.windowID, releasingProfiles: [])
    }

}
