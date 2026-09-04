import SwiftUI

struct BrowserExtensionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: 12, minHeight: 12)
            .fixedSize()
            .background(.red, in: .capsule)
            .offset(x: 5, y: -5)
    }
}
