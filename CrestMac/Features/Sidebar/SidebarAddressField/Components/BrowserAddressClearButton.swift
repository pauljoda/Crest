import SwiftUI

struct BrowserAddressClearButton: View {
    @Binding var text: String

    var body: some View {
        Button("Clear", systemImage: "xmark.circle.fill") {
            text = ""
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
    }
}

#Preview {
    @Previewable @State var text = "https://example.com"

    BrowserAddressClearButton(text: $text)
        .padding()
}
