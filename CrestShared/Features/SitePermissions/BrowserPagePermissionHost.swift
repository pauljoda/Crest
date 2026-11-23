import SwiftUI

/// Lets a view show its page's permission requests while it is on screen.
/// Each host attaches by its own identity, so a page that moves to another
/// window keeps the new window's host whichever leaves or arrives first.
private struct BrowserPagePermissionHost: ViewModifier {
    let controller: BrowserPagePermissionController?
    @State private var identity = UUID()
    @State private var attachedController: BrowserPagePermissionController?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: attach)
            .onChange(of: controller.map(ObjectIdentifier.init)) { attach() }
            .onDisappear {
                attachedController?.detachHost(identity)
                attachedController = nil
            }
    }

    private func attach() {
        guard attachedController !== controller else { return }
        attachedController?.detachHost(identity)
        attachedController = controller
        controller?.attachHost(identity)
    }
}

extension View {
    func pagePermissionHost(_ controller: BrowserPagePermissionController?) -> some View {
        modifier(BrowserPagePermissionHost(controller: controller))
    }
}
