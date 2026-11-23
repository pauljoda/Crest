import SwiftUI

/// The Site Controls button beside a page's address, and the popover of the
/// page's Site Controls it opens. A permission request the page makes opens
/// it on its own, waiting under the actions; a command such as Show QR Code
/// opens it on one of its pages.
struct BrowserSiteControlButton: View {
    // MARK: - Types

    /// Whether the control is on screen, held by reference so a check made
    /// after its popover closes reads the control as it is then.
    @MainActor
    private final class Presence {
        var isOnScreen = false
    }

    // MARK: - Variables

    let configuration: BrowserSiteControlConfiguration

    @State private var isPresented = false
    @State private var presence = Presence()
    /// The open Site Controls, made when the popover opens and dropped when
    /// it closes, so each opening starts at the root.
    @State private var model: SiteControlsModel?
    @Environment(\.browserSiteControlAnchor) private var anchor
    @Environment(\.browserWindowCommands) private var commands

    var body: some View {
        BrowserSiteControlTrigger(
            isPresented: presentationBinding,
            blockedPopupNotice: configuration.page.blockedPopupNotice,
            waitsOnPermission: configuration.page.sitePermissionRequests.current != nil
        )
        .crestPopover(isPresented: presentationBinding, arrowEdge: .top) {
            if let model {
                SiteControlsView(model: model) { openPage in
                    BrowserEngineSiteControlsTiles(
                        page: configuration.page, space: configuration.space, url: configuration.page.live.documentURL,
                        dismiss: { dismiss() }, openPage: openPage)
                } extensionsPage: {
                    BrowserEngineSiteControlsExtensionsPage(
                        page: configuration.page, space: configuration.space, url: configuration.page.live.documentURL,
                        dismiss: { dismiss() })
                }
                .environment(\.siteControlsMetrics, .popover)
                .accessibilityIdentifier("browser-site-controls-popover")
            }
        }
        // This control opens the window's extension list, so it is where an
        // extension popup goes when the keyboard asked for one and the
        // extension has no pinned tile to anchor to.
        .background {
            if let anchor { BrowserSiteControlAnchorHost(anchor: anchor) }
        }
        .pagePermissionHost(configuration.page.sitePermissionRequests)
        .onChange(of: configuration.page.sitePermissionRequests.current?.id) {
            // A request opens Site Controls on its own, at the root where it
            // waits, and asks to be remembered as any new request does; once
            // it is answered, they close again unless the person opened them.
            model?.remembersPermission = true
            if configuration.page.sitePermissionRequests.current != nil {
                openForRequest()
                model?.showRoot()
            } else if !isPresented {
                model = nil
            }
            configuration.presentationChanged(presentationBinding.wrappedValue)
        }
        .onChange(of: commands?.actions.chrome.siteControlsRequest) { takeRequest() }
        .onAppear {
            presence.isOnScreen = true
            if configuration.page.sitePermissionRequests.current != nil { openForRequest() }
            takeRequest()
        }
        .onDisappear {
            presence.isOnScreen = false
            guard isPresented else { return }
            presentationBinding.wrappedValue = false
        }
        .onChange(of: BrowserSpaceRuntimeAssignment(space: configuration.space)) {
            // The stationary address field survives a Space change; its old
            // site's popover must still end at that assignment boundary.
            guard isPresented else { return }
            presentationBinding.wrappedValue = false
        }
    }

    // MARK: - Actions - Presentation

    /// Opens Site Controls on the page a command asked for, when it asked for
    /// this control's page.
    private func takeRequest() {
        guard let chrome = commands?.actions.chrome,
            let destination = chrome.takeSiteControlsRequest(for: configuration.page)
        else { return }
        if let model {
            model.open(destination)
        } else {
            prepare(opening: destination)
        }
        presentationBinding.wrappedValue = true
    }

    /// Opens Site Controls for a waiting request, focusing a split card first
    /// so the commands they run act on the card that asked.
    private func openForRequest() {
        focusCard()
        prepare(opening: nil)
    }

    /// Makes the Site Controls the popover shows, on `destination` or the
    /// root, unless they are open already.
    private func prepare(opening destination: SiteControlsPage?) {
        guard model == nil, let commands else { return }
        let controls = BrowserMacSiteControls(
            configuration: configuration, actions: commands.actions, shortcuts: commands.shortcuts
        ) { [binding = presentationBinding] in binding.wrappedValue = false }
        model = SiteControlsModel(platform: controls, page: destination)
    }

    /// Puts Site Controls away, as an extension that leads elsewhere does.
    private func dismiss() {
        presentationBinding.wrappedValue = false
    }

    /// The person closed the popover over a waiting request, which dismisses
    /// it. A window closing, or its page moving to another window, closes the
    /// popover too, and takes the control off screen in the same turn: that
    /// leaves the request for the page's next window.
    private func dismissPermissionRequests() {
        let (controller, presence) = (configuration.page.sitePermissionRequests, presence)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard presence.isOnScreen else { return }
                controller.cancelAll()
            }
        }
    }

    /// A split card's Site Controls act for its tab, so opening them focuses
    /// the card, which the tab and page commands follow.
    private func focusCard() {
        guard let tabID = configuration.selectedTabID, let actions = commands?.actions,
            actions.browser.shownTab?.id != tabID,
            actions.presentedSplitMembers.contains(where: { $0.id == tabID })
        else { return }
        actions.browser.selectTab(tabID)
        actions.pages.select()
    }

    private var presentationBinding: Binding<Bool> {
        Binding {
            (isPresented || configuration.page.sitePermissionRequests.current != nil) && model != nil
        } set: { isPresented in
            if !isPresented && configuration.page.sitePermissionRequests.current != nil {
                dismissPermissionRequests()
            }
            if isPresented {
                focusCard()
                prepare(opening: nil)
            }
            guard isPresented != self.isPresented else {
                if !isPresented { model = nil }
                return
            }
            self.isPresented = isPresented
            if !isPresented { model = nil }
            configuration.presentationChanged(isPresented)
        }
    }
}
