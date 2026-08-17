import SwiftUI

struct BrowserExtensionValueList: View {
    let title: LocalizedStringKey
    let values: [String]
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            Text(title)
                .font(.caption.weight(.semibold))
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: symbol)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }
}
