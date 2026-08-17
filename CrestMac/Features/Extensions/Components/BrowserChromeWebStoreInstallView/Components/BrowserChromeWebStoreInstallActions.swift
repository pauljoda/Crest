import SwiftUI

struct BrowserChromeWebStoreInstallActions: View {
    let page: BrowserPage
    let phase: BrowserChromeWebStoreInstallPhase

    var body: some View {
        HStack {
            if case .failed = phase {
                Button("Try Again", action: page.retryChromeWebStorePreparation)
                    .disabled(page.isPreparingChromeWebStoreExtension)
            }

            Spacer()

            switch phase {
            case .installed:
                Button("Done", action: page.dismissChromeWebStoreInstall)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .unavailable, .preparing, .failed:
                cancelButton
            case .review(let candidate, _):
                cancelButton
                Button(action: page.installPreparedChromeWebStoreExtension) {
                    if page.isInstallingChromeWebStoreExtension {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Adding extension")
                    } else {
                        Text("Add Extension")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    page.isInstallingChromeWebStoreExtension
                        || !candidate.compatibility.canRun
                )
            }
        }
    }

    private var cancelButton: some View {
        Button(
            "Cancel",
            role: .cancel,
            action: page.dismissChromeWebStoreInstall
        )
        .disabled(page.isInstallingChromeWebStoreExtension)
    }
}
