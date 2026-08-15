import SwiftUI

struct BrowserDeveloperAddressField: View {
    @Binding var address: String
    let navigate: @MainActor () -> Void

    var body: some View {
        TextField("Full URL", text: $address)
            .textFieldStyle(.plain)
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .lineLimit(1)
            .onSubmit(navigate)
            .accessibilityLabel("Developer URL")
            .accessibilityIdentifier("developer-url-field")
    }
}

#Preview("Developer Address Field") {
    @Previewable @State var address = "https://example.com"
    BrowserDeveloperAddressField(address: $address, navigate: {})
        .padding()
        .frame(width: 360)
}
