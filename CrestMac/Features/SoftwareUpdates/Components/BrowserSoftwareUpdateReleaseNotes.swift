import SwiftUI

struct BrowserSoftwareUpdateReleaseNotes: View {
    let releaseNotes: String

    var body: some View {
        GroupBox("Release Notes") {
            ScrollView {
                Group {
                    if let attributedNotes = try? AttributedString(
                        markdown: releaseNotes
                    ) {
                        Text(attributedNotes)
                    } else {
                        Text(releaseNotes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 240)
        }
    }
}

#Preview {
    BrowserSoftwareUpdateReleaseNotes(
        releaseNotes: "## What’s new\n\n- Native software updates\n- Security fixes"
    )
    .frame(width: 520)
    .padding()
}
