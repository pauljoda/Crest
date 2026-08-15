import SwiftUI

struct BrowserSoftwareUpdateStatusHeader: View {
    let model: BrowserSoftwareUpdateModel

    var body: some View {
        HStack(alignment: .top, spacing: CrestSpacing.medium) {
            Image(systemName: symbolName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(symbolStyle)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text(title)
                    .font(.title2.weight(.semibold))

                if let message = model.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var title: String {
        switch model.phase {
        case .idle: "Software Update"
        case .permission: "Keep Crest Up to Date"
        case .checking: "Checking for Updates"
        case .updateAvailable: model.updateTitle ?? "Update Available"
        case .downloading: "Downloading Update"
        case .extracting: "Preparing Update"
        case .readyToInstall: "Ready to Install"
        case .installing: "Installing Update"
        case .upToDate: "Crest Is Up to Date"
        case .failed: "Update Check Failed"
        case .installed: "Update Installed"
        }
    }

    private var symbolName: String {
        switch model.phase {
        case .failed: "exclamationmark.triangle.fill"
        case .upToDate, .installed: "checkmark.circle.fill"
        case .downloading: "arrow.down.circle.fill"
        case .readyToInstall, .installing: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
        default: "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch model.phase {
        case .failed: AnyShapeStyle(.orange)
        case .upToDate, .installed: AnyShapeStyle(.green)
        default: AnyShapeStyle(CrestBrandTheme.accent)
        }
    }
}

#Preview("Up to Date") {
    let model = BrowserSoftwareUpdateModel()
    BrowserSoftwareUpdateStatusHeader(model: model)
        .frame(width: 520, alignment: .leading)
        .padding()
        .task {
            model.presentNoUpdate(
                message: "Crest 0.3 is the newest version available.",
                acknowledgement: {}
            )
        }
}
