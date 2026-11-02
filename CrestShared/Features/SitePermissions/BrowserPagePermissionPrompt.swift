import SwiftUI

struct BrowserPagePermissionPrompt: View {
    let request: BrowserPagePermissionController.Request
    let controller: BrowserPagePermissionController

    @State private var remembersChoice = true
    @Environment(\.colorScheme) private var colorScheme

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
                // Deny is the plain choice beside Allow, never a second accent.
                .tint(.primary)
                Button {
                    controller.resolve(
                        request.id,
                        response: remembersChoice ? .grantPersistently : .allowOnce
                    )
                } label: {
                    Text("Allow")
                        .frame(maxWidth: .infinity)
                        .browserReadableForeground(over: allowTint)
                }
                .buttonStyle(.borderedProminent)
                .tint(allowTint)
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .onChange(of: request.id) { remembersChoice = true }
    }

    /// Allow wears Crest's accent, never a Space's, whose tint can be as light
    /// as the label on it; the label takes whichever ink reads on the tint.
    private var allowTint: Color {
        CrestBrandTheme.accent(colorScheme)
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

extension View {
    func pagePermissionHost(_ controller: BrowserPagePermissionController?) -> some View {
        modifier(BrowserPagePermissionHost(controller: controller))
    }
}
