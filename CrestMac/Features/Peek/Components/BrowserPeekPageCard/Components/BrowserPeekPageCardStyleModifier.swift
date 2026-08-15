import SwiftUI

struct BrowserPeekPageCardStyleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            }
            .shadow(
                color: .black.opacity(reduceTransparency ? 0 : 0.34),
                radius: 28,
                y: 14
            )
    }
}

#Preview {
    Rectangle()
        .fill(.background)
        .frame(width: 640, height: 420)
        .modifier(BrowserPeekPageCardStyleModifier(reduceTransparency: false))
        .padding(40)
}
