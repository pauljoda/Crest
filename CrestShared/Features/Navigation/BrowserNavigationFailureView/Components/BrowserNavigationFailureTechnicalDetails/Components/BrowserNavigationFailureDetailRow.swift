import SwiftUI

struct BrowserNavigationFailureDetailRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
        } label: {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Navigation Failure Detail Row") {
    BrowserNavigationFailureDetailRow(
        label: "Error Domain",
        value: "NSURLErrorDomain"
    )
    .padding()
}
