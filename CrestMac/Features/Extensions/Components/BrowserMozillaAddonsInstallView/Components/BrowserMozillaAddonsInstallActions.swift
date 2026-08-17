import SwiftUI

struct BrowserMozillaAddonsInstallActions: View {
    let session: BrowserMozillaAddonsInstallSession
    let phase: BrowserMozillaAddonsInstallPhase

    var body: some View {
        HStack {
            if case .failed = phase {
                Button("Try Again", action: session.retryPreparation)
                    .disabled(session.isPreparing)
            }

            Spacer()

            switch phase {
            case .installed:
                Button("Done", action: session.dismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .unavailable, .preparing, .failed:
                cancelButton
            case .review(let candidate, _):
                cancelButton
                Button(action: session.installPrepared) {
                    if session.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Adding add-on")
                    } else {
                        Text("Add Extension")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    session.isInstalling
                        || !candidate.compatibility.canRun
                )
            }
        }
    }

    private var cancelButton: some View {
        Button(
            "Cancel",
            role: .cancel,
            action: session.dismiss
        )
        .disabled(session.isInstalling)
    }
}
