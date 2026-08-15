import SwiftUI

struct BrowserSoftwareUpdateActions: View {
    let model: BrowserSoftwareUpdateModel

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            switch model.phase {
            case .permission:
                Button("Not Now") {
                    model.chooseAutomaticChecks(false)
                }
                Spacer()
                Button("Check Automatically") {
                    model.chooseAutomaticChecks(true)
                }
                .buttonStyle(.borderedProminent)
            case .checking, .downloading:
                Spacer()
                Button("Cancel", action: model.cancelCurrentOperation)
            case .updateAvailable:
                Button("Skip This Version", action: model.skipUpdate)
                Spacer()
                Button("Later", action: model.dismissUpdate)
                if model.isInformationOnly, let informationURL = model.informationURL {
                    Link("View Release", destination: informationURL)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Download and Install", action: model.installUpdate)
                        .buttonStyle(.borderedProminent)
                }
            case .readyToInstall:
                Button("Later", action: model.dismissUpdate)
                Spacer()
                Button("Install and Relaunch", action: model.installAndRelaunchNow)
                    .buttonStyle(.borderedProminent)
            case .installing:
                Spacer()
                if model.canRetryTermination {
                    Button(
                        "Try Quitting Again",
                        action: model.retryApplicationTermination
                    )
                }
            case .upToDate, .failed, .installed:
                Spacer()
                Button("OK", action: model.acknowledge)
                    .keyboardShortcut(.defaultAction)
            case .idle, .extracting:
                EmptyView()
            }
        }
        .tint(CrestBrandTheme.accent)
    }
}

#Preview("Update Available") {
    let model = BrowserSoftwareUpdateModel()
    BrowserSoftwareUpdateActions(model: model)
        .frame(width: 520)
        .padding()
        .task {
            model.presentUpdate(
                title: "Crest 0.4",
                version: "0.4.0",
                isInformationOnly: false,
                install: {},
                dismiss: {},
                skip: {}
            )
        }
}
