import SwiftUI

struct BrowserExtensionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: 12, minHeight: 12)
            .background(.red, in: .capsule)
            .offset(x: 5, y: -5)
    }
}

#Preview("Extension Badge") {
    BrowserExtensionBadge(text: "3")
        .padding()
}
