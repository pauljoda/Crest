import AppKit
import SwiftUI

// MARK: - Types

/// The stores a focused browser window presents, which the menu bar's and the
/// engine's commands act on.
struct BrowserMacWindowContext {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let windowID: UUID
}

extension EnvironmentValues {
    /// The shell's windows, which every window's content can open others
    @Entry var browserMacWindows: BrowserMacWindows? = nil
}

/// Every window the shell opens, by kind and identity: it opens each one, or
/// brings forward the one already open under its identity, knows which one
/// the person is using, and lets go of what goes with each as it closes.
@MainActor
final class BrowserMacWindows {
    // MARK: - Variables

    unowned let application: BrowserMacApplication
    unowned let engineHost: any BrowserMacEngineHost

    /// The engine and version the build runs pages in, where it names one,
    /// as About Crest credits it.
    var engineCredits: String? { engineHost.aboutCredits }

    /// The windows open now, in the order they opened.
    var controllers: [BrowserMacWindowController] = []
    /// The content of each Quick Window open now, by its identity.
    var quickWindows: [UUID: QuickWindow] = [:]
    /// The windows this launch opens, held back while first-run setup stands
    /// in front of them.
    private var heldLaunch: LaunchWindowPlan?

    /// The window of the person's Spaces they are using: the key one, or the
    /// main one, or any.
    var activeBrowserWindow: NSWindow? {
        let browsing = controllers.filter(\.kind.hasWindowModel).map(\.window)
        if let key = NSApp.keyWindow, browsing.contains(where: { $0 === key }) { return key }
        return browsing.first { $0.isMainWindow } ?? browsing.first
    }

    /// The model of the key window, when it is a browser window over the
    /// person's own Spaces.
    var activeWindowModel: BrowserMacWindowModel? {
        guard let key = controller(showing: NSApp.keyWindow), key.kind.hasWindowModel else { return nil }
        return application.windowCoordinator.existingModel(for: key.windowID)
    }

    /// The stores of the key window, when it is a browser or the private window.
    var activeContext: BrowserMacWindowContext? {
        if controller(showing: NSApp.keyWindow)?.kind == .private {
            return BrowserMacWindowContext(
                browser: application.privateBrowser, pages: application.privatePages,
                chrome: application.privateChrome, windowID: application.privatePages.windowID)
        }
        return activeWindowModel.map(Self.context(of:))
    }

    /// The menu bar's commands as they run in the key browser window.
    var activeActions: BrowserCommandActions? {
        guard let context = activeContext else { return nil }
        return BrowserCommandActions(
            browser: context.browser, pages: context.pages, chrome: context.chrome, windows: self,
            spaceAccess: application.spaceAccess, targetWindowID: context.windowID)
    }

    /// Whether the key window is a Quick Window.
    var isQuickWindowKey: Bool {
        controller(showing: NSApp.keyWindow)?.kind == .quick
    }

    /// Whether the key window is one the shell opened, which the menu bar's
    /// close commands close even when it shows no browser.
    var isShellWindowKey: Bool {
        controller(showing: NSApp.keyWindow) != nil
    }

    /// The window a Dock click brings forward: the browser window the person
    /// used, or else the private window, a Quick Window or setup.
    var windowToBringForward: BrowserMacWindowController? {
        if let window = activeBrowserWindow, let controller = controller(showing: window) { return controller }
        return [BrowserMacWindowKind.private, .quick, .setup].lazy.compactMap { kind in
            self.controllers.first { $0.kind == kind }
        }.first
    }

    // MARK: - Initializers

    init(application: BrowserMacApplication, engineHost: any BrowserMacEngineHost) {
        self.application = application
        self.engineHost = engineHost
    }

    // MARK: - Actions - Lookup

    /// The window open under the core's identity `id`, or with none, the
    /// window an engine surface with no window of its own is shown in.
    func window(for id: UUID?) -> NSWindow? {
        guard let id else { return controllers.first(where: \.kind.hasWindowModel)?.window }
        return controllers.first { $0.windowID == id && $0.kind.identifier == nil }?.window
    }

    /// The identity of the browser window `window` is, over the person's own
    /// Spaces, or nil.
    func browserWindowID(of window: NSWindow) -> UUID? {
        controller(showing: window).flatMap { $0.kind.hasWindowModel ? $0.windowID : nil }
    }

    /// The identity of the window `window` is, when it shows a page row that
    /// can hold a side panel, or nil for setup, a Quick Window or any window
    /// the shell did not open.
    func pageRowWindowID(of window: NSWindow) -> UUID? {
        controller(showing: window).flatMap { $0.kind.hasPageRow ? $0.windowID : nil }
    }

    /// Whether a browser window is open under `id`.
    func isBrowserWindowOpen(_ id: UUID) -> Bool {
        controllers.contains { $0.kind.hasWindowModel && $0.windowID == id }
    }

    /// Whether `id` is the private window's identity while it is open.
    func isPrivateWindow(_ id: UUID) -> Bool {
        controllers.contains { $0.kind == .private && $0.windowID == id }
    }

    /// The stores of the window a menu command that needs a browser window
    /// runs in: the key browser or private window; else the browser window the
    /// person used, brought forward; else a new browser window. A Quick Window
    /// or setup being key never opens another window for the command.
    func contextBringingBrowserWindowForward() -> BrowserMacWindowContext? {
        if let context = activeContext { return context }
        let coordinator = application.windowCoordinator
        if let window = activeBrowserWindow, let controller = controller(showing: window),
            let model = coordinator.existingModel(for: controller.windowID)
        {
            controller.bringForward()
            return Self.context(of: model)
        }
        let request = BrowserMacWindowRequest.normal(sourceWindowID: nil)
        open(request, activation: .key)
        return coordinator.existingModel(for: request.id).map(Self.context(of:))
    }

    private static func context(of model: BrowserMacWindowModel) -> BrowserMacWindowContext {
        BrowserMacWindowContext(
            browser: model.browser, pages: model.pages, chrome: model.chrome, windowID: model.id)
    }

    private func controller(showing window: NSWindow?) -> BrowserMacWindowController? {
        guard let window else { return nil }
        return controllers.first { $0.window === window }
    }

    func controller(_ kind: BrowserMacWindowKind, id: UUID? = nil) -> BrowserMacWindowController? {
        controllers.first { $0.kind == kind && (id == nil || $0.windowID == id) }
    }

    /// Brings forward the window of `kind` already open, when one window of
    /// the kind is open at a time. Answers whether there was one.
    func bringForwardOpenWindow(of kind: BrowserMacWindowKind) -> Bool {
        guard kind.isSingleton, let existing = controller(kind) else { return false }
        existing.present(.key)
        return true
    }

    // MARK: - Actions - Launch

    /// Opens what the core says this launch opens: the windows the person
    /// left open, or first-run setup in front of them, which holds them back
    /// until it finishes. Private and Quick Windows are never restored.
    func openLaunchWindows(activation: BrowserMacWindowActivation = .key) {
        guard
            let plan = try? application.browser.core.query(LaunchWindows(environment: application.launchEnvironment))
        else {
            open(.initial, activation: activation)
            return
        }
        if let setup = plan.setup {
            heldLaunch = plan
            openOnboardingWindow(BrowserOnboardingRequest(entryPoint: setup), activation: activation)
            return
        }
        open(plan, activation: activation)
    }

    /// Opens the launch's windows back to front, each coming forward without
    /// focus, and the frontmost last, as the key window on the startup choice.
    private func open(_ plan: LaunchWindowPlan, activation: BrowserMacWindowActivation = .key) {
        heldLaunch = nil
        application.startupWindowID = plan.startupWindowID
        for id in plan.windowIDs {
            open(.reopening(id), activation: id == plan.startupWindowID ? activation : .background)
        }
    }

    // MARK: - Actions - Browser windows

    /// Opens the browser window `request` names, or brings forward the one
    /// open under its identity, as `activation` says.
    func open(_ request: BrowserMacWindowRequest, activation: BrowserMacWindowActivation) {
        let kind = BrowserMacWindowKind.browsing(request)
        if let existing = controllers.first(where: { $0.kind.hasWindowModel && $0.windowID == request.id }) {
            existing.present(activation)
            return
        }
        guard let model = application.windowCoordinator.model(for: request) else { return }
        show(
            kind, id: request.id, closeGate: model.closeGate,
            cascadingFrom: NSApp.keyWindow.flatMap { browserWindowID(of: $0) == nil ? nil : $0 },
            activation: activation, content: { _ in application.browserWindowContent(model) },
            closed: { [weak self] controller in
                self?.forget(controller)
                // The core forgets a window the person closed for the next
                // launch, and keeps the ones still open once a quit was allowed.
                self?.application.windowCoordinator.closeWindow(controller.windowID)
            })
    }

    // MARK: - Actions - Setup

    /// Opens setup for `request`. Asking again brings its current draft
    /// forward.
    func openOnboardingWindow(_ request: BrowserOnboardingRequest, activation: BrowserMacWindowActivation = .key) {
        guard !bringForwardOpenWindow(of: .setup) else { return }
        let source = activeWindowModel
        show(
            .setup, activation: activation,
            content: { window in
                BrowserOnboardingWindow(
                    request: request, browser: source?.browser ?? application.browser,
                    cloudSync: application.cloudSync, progress: application.onboardingProgress,
                    spaceAccess: application.spaceAccess, extensionInstaller: engineHost.importedExtensionInstaller,
                    closeWindow: { [weak window] in window?.close() },
                    openBrowser: { [weak self] in self?.openBrowser(after: source?.id) })
            },
            closed: { [weak self] controller in self?.forget(controller) })
    }

    /// Setup finished: the window it was opened from comes forward, or the
    /// launch it held back opens, or else a new browser window.
    private func openBrowser(after sourceWindowID: UUID?) {
        if let sourceWindowID,
            let source = controllers.first(where: { $0.kind.hasWindowModel && $0.windowID == sourceWindowID })
        {
            source.present(.key)
        } else if let heldLaunch {
            open(heldLaunch)
        } else {
            open(.normal(sourceWindowID: nil), activation: .key)
        }
    }

    // MARK: - Actions - Update details

    /// The release notes for the update the sidebar card presents. One window,
    /// brought forward when asked again, and never restored at launch.
    func openSoftwareUpdateDetails() {
        guard !bringForwardOpenWindow(of: .updateDetails) else { return }
        show(
            .updateDetails,
            content: { window in
                BrowserSoftwareUpdateDetailsView(
                    model: application.softwareUpdates.model, closeWindow: { [weak window] in window?.close() }
                ).tint(CrestBrandTheme.accent)
            },
            closed: { [weak self] controller in self?.forget(controller) })
    }

    // MARK: - Actions - Presenting

    /// Opens a window of `kind` under `id` showing `content`, which opens
    /// other windows through these, places it cascading from `source` and
    /// brings it forward as `activation` says. `closed` says what goes with it.
    func show<Content: View>(
        _ kind: BrowserMacWindowKind, id: UUID = UUID(), closeGate: BrowserWindowCloseGate? = nil,
        cascadingFrom source: NSWindow? = nil, activation: BrowserMacWindowActivation = .key,
        content: (BrowserMacWindow) -> Content, closed: @escaping @MainActor (BrowserMacWindowController) -> Void
    ) {
        let controller = BrowserMacWindowController(
            kind: kind, windowID: id, closeGate: closeGate,
            content: { window in content(window).environment(\.browserMacWindows, self) }, closed: closed)
        controllers.append(controller)
        controller.place(cascadingFrom: source)
        controller.present(activation)
    }

    // MARK: - Mutators

    func forget(_ controller: BrowserMacWindowController) {
        controllers.removeAll { $0 === controller }
    }
}
