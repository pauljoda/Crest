import SwiftUI

struct MobileStrongPasswordExplanation: View {
    let spaceName: String

    var body: some View {
        Text(
            "Crest fills a unique 20-character password here and in its confirmation field. It is saved only after you submit and confirm the \(spaceName) prompt."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
