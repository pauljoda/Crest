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
                    Text(requestDescription)
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

    private var requestDescription: LocalizedStringKey {
        switch request.permission {
        case .camera: "Wants to use your camera"
        case .microphone: "Wants to use your microphone"
        case .cameraAndMicrophone: "Wants to use your camera and microphone"
        case .notifications: "Wants to send notifications while this page is open"
        case .location: "Wants to use your location"
        case .automaticDownloads: "Wants to download multiple files automatically"
        default: "Requests permission"
        }
    }
}

private struct BrowserPagePermissionHost: ViewModifier {
    let controller: BrowserPagePermissionController?
    @State private var attachedController: BrowserPagePermissionController?

    func body(content: Content) -> some View {
        content
            .onChange(of: controller.map(ObjectIdentifier.init), initial: true) {
                attachedController?.setPresentationAvailable(false)
                attachedController = controller
                controller?.setPresentationAvailable(true)
            }
            .onDisappear {
                attachedController?.setPresentationAvailable(false)
                attachedController = nil
            }
    }
}

extension View {
    func pagePermissionHost(_ controller: BrowserPagePermissionController?) -> some View {
        modifier(BrowserPagePermissionHost(controller: controller))
    }
}
