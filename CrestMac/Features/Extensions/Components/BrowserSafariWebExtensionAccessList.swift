import SwiftUI

struct BrowserSafariWebExtensionAccessList: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("\(title) (\(values.count))")
                .font(.caption.weight(.semibold))
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }
}
