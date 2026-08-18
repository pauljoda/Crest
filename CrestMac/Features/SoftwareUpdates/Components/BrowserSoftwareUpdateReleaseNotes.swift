import SwiftUI

struct BrowserSoftwareUpdateReleaseNotes: View {
    private let document: BrowserSoftwareUpdateReleaseNotesDocument

    init(releaseNotes: String) {
        document = BrowserSoftwareUpdateReleaseNotesDocument(markdown: releaseNotes)
    }

    var body: some View {
        GroupBox {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CrestSpacing.small) {
                    ForEach(document.blocks.indices, id: \.self) { index in
                        BrowserSoftwareUpdateReleaseNoteBlock(
                            block: document.blocks[index]
                        )
                    }
                }
                .padding(CrestSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(minHeight: 200, maxHeight: 320)
        } label: {
            Label("Release Notes", systemImage: "text.alignleft")
        }
        .tint(CrestBrandTheme.accent)
    }
}
