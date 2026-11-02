import SwiftUI

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
    @Environment(\.browserSiteControlAnchor) private var anchor

    var body: some View {
        BrowserSiteControlTrigger(
            isPresented: presentationBinding,
            blockedPopupNotice: configuration.page.blockedPopupNotice
        )
        .popover(isPresented: presentationBinding, arrowEdge: .top) {
            Group {
                if let request = configuration.page.sitePermissionRequests.current {
                    BrowserPagePermissionPrompt(
                        request: request,
                        controller: configuration.page.sitePermissionRequests
                    )
                } else {
                    BrowserSiteControlPopover(
                        configuration: configuration,
                        dismiss: { presentationBinding.wrappedValue = false }
                    )
                }
            }
            .font(.body)
            .crestFlyoutStyle()
        }
        // This control opens the window's extension list, so it is where an
        // extension popup goes when the keyboard asked for one and the
        // extension has no pinned tile to anchor to.
        .background {
            if let anchor { BrowserSiteControlAnchorHost(anchor: anchor) }
        }
        .pagePermissionHost(configuration.page.sitePermissionRequests)
        .onChange(of: configuration.page.sitePermissionRequests.current?.id) {
            configuration.presentationChanged(presentationBinding.wrappedValue)
        }
        .onAppear { presence.isOnScreen = true }
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

    private var presentationBinding: Binding<Bool> {
        Binding {
            isPresented || configuration.page.sitePermissionRequests.current != nil
        } set: { isPresented in
            if !isPresented && configuration.page.sitePermissionRequests.current != nil {
                dismissPermissionRequests()
            }
            guard isPresented != self.isPresented else { return }
            self.isPresented = isPresented
            configuration.presentationChanged(isPresented)
        }
    }
}
