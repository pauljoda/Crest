import SwiftUI

struct BrowserPagePermissionPrompt: View {
    let request: BrowserPagePermissionController.Request
    let controller: BrowserPagePermissionController

    @State private var remembersChoice = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: request.permission.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.origin.displayName)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.permission.requestTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if request.origin != request.topLevelOrigin {
                        Text("Inside \(request.topLevelOrigin.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button("Dismiss Permission Request", systemImage: "xmark") {
                    controller.cancelAll()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }
            Toggle("Remember in \(request.spaceName)", isOn: $remembersChoice)
                .font(.caption)
                #if os(macOS)
                    .toggleStyle(.checkbox)
                #endif
            HStack(spacing: 8) {
                Button {
                    controller.resolve(
                        request.id,
                        response: remembersChoice ? .denyPersistently : .denyOnce
                    )
                } label: {
                    Text("Deny").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    controller.resolve(
                        request.id,
                        response: remembersChoice ? .grantPersistently : .allowOnce
                    )
                } label: {
                    Text("Allow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .onChange(of: request.id) { remembersChoice = true }
    }
}

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

/// Shows a page's permission requests in a popover from this view, for a
/// surface with no site controls of its own to present them.
private struct BrowserPagePermissionPopover: ViewModifier {
    let controller: BrowserPagePermissionController?

    func body(content: Content) -> some View {
        // Read here, not only inside the binding, so a new request updates
        // this view and opens the popover.
        let shown = controller?.current
        content
            .popover(item: requestBinding(shown), arrowEdge: .bottom) { request in
                if let controller {
                    BrowserPagePermissionPrompt(request: request, controller: controller)
                }
            }
            .pagePermissionHost(controller)
    }

    /// Closing the popover on `shown` without an answer dismisses the
    /// waiting requests, which saves nothing. Once `shown` is answered the
    /// popover closes for it on its way to the next request, which must
    /// keep waiting, so only a close while `shown` still waits dismisses.
    private func requestBinding(
        _ shown: BrowserPagePermissionController.Request?
    ) -> Binding<BrowserPagePermissionController.Request?> {
        Binding {
            shown
        } set: { request in
            guard request == nil, let shown, controller?.current?.id == shown.id else { return }
            controller?.cancelAll()
        }
    }
}

extension View {
    func pagePermissionHost(_ controller: BrowserPagePermissionController?) -> some View {
        modifier(BrowserPagePermissionHost(controller: controller))
    }

    func pagePermissionPopover(_ controller: BrowserPagePermissionController?) -> some View {
        modifier(BrowserPagePermissionPopover(controller: controller))
    }
}
