import SwiftUI

struct BrowserSoftwareUpdateView: View {
    let model: BrowserSoftwareUpdateModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            BrowserSoftwareUpdateStatusHeader(model: model)

            if let progress = model.progress {
                BrowserSoftwareUpdateProgress(progress: progress)
            } else if model.phase == .checking || model.phase == .extracting
                || model.phase == .installing
            {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Software update progress")
            }

            if let releaseNotes = model.releaseNotes,
                !releaseNotes.isEmpty
            {
                BrowserSoftwareUpdateReleaseNotes(releaseNotes: releaseNotes)
            }

            Spacer(minLength: 0)

            BrowserSoftwareUpdateActions(model: model)
        }
        .padding(CrestSpacing.extraLarge)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 260, idealHeight: 440)
        .background(CrestBrandTheme.canvas)
        .onChange(of: model.phase) { _, phase in
            guard phase == .idle else { return }
            dismissWindow(id: BrowserSceneID.softwareUpdate.rawValue)
        }
        .onDisappear {
            model.closePresentation()
        }
    }
}

#Preview("Update Available") {
    let model = BrowserSoftwareUpdateModel()
    BrowserSoftwareUpdateView(model: model)
        .task {
            model.presentUpdate(
                title: "Crest 0.4",
                version: "0.4.0",
                releaseNotes: """
                    ## Highlights

                    ### New

                    - Native software updates

                    ### Fixed

                    - Restored extension pages after relaunch

                    ---

                    [View all changes](https://crestbrowser.com/)
                    """,
                isInformationOnly: false,
                install: {},
                dismiss: {},
                skip: {}
            )
        }
}
