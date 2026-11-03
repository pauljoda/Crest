import SwiftUI

struct BrowserCrestStudioTextField: View {
    let title: LocalizedStringKey
    var symbol = "textformat"
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                TextField(title, text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .autocorrectionDisabled()
            }
            .crestFieldSurface(isFocused: isFocused)
        }
    }
}
