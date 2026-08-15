import SwiftUI

struct BrowserDataPortabilityProgressStatus: View {
    let model: BrowserDataPortabilityModel

    var body: some View {
        if model.isPreparingExport || model.isPreparingBookmarkExport {
            ProgressView(
                model.isPreparingBookmarkExport
                    ? "Preparing bookmarks…"
                    : "Preparing browser data…"
            )
        }

        if let status = model.status {
            Label {
                switch status.message {
                case .localized(let message):
                    Text(message)
                case .verbatim(let message):
                    Text(message)
                }
            } icon: {
                Image(systemName: status.symbol)
            }
            .foregroundStyle(status.isError ? .red : .secondary)
            .font(.footnote)
            .accessibilityIdentifier("browser-data-operation-status")
        }
    }
}

#Preview("Operation Status") {
    let model = BrowserDataPortabilityPreviewFixture.makeModel()
    model.status = BrowserDataPortabilityOperationStatus("Browser data exported.")
    return Form {
        BrowserDataPortabilityProgressStatus(model: model)
    }
    .frame(width: 620)
}
