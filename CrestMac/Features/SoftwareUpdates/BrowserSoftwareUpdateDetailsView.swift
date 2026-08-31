import SwiftUI

/// Full release notes for an update the sidebar is already presenting.
///
/// This scene is deliberately passive: closing it never changes Sparkle's
/// pending choice, and only the sidebar's explicit What's New control opens it.
struct BrowserSoftwareUpdateDetailsView: View {
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

            if let releaseNotes = model.releaseNotes, !releaseNotes.isEmpty {
                BrowserSoftwareUpdateReleaseNotes(releaseNotes: releaseNotes)
            } else if let informationURL = model.informationURL {
                Link("View the full release notes", destination: informationURL)
            }

            Spacer(minLength: 0)

            BrowserSoftwareUpdateActions(model: model)
        }
        .padding(CrestSpacing.extraLarge)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 260, idealHeight: 440)
        .background(CrestBrandTheme.canvas)
        .onChange(of: model.phase, initial: true) { _, phase in
            guard phase == .idle else { return }
            dismissWindow(id: BrowserSoftwareUpdateSceneID.details)
        }
    }
}

#Preview("Update Details") {
    let model = BrowserSoftwareUpdateModel()
    BrowserSoftwareUpdateDetailsView(model: model)
        .task {
            model.presentUpdate(
                title: "Crest 0.5.99",
                version: "0.5.99",
                releaseNotes: """
                    ## Highlights

                    ### Improved

                    - Software updates now stay in the sidebar.

                    ### Fixed

                    - Update details open only when requested.
                    """,
                isInformationOnly: false,
                install: {},
                skip: {}
            )
        }
}
