import SwiftUI

struct SidebarTabTrailingControlLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(
                .system(
                    size: BrowserTabTrailingControlPolicy.glyphSize,
                    weight: .regular
                )
            )
            .frame(
                width: BrowserTabTrailingControlPolicy.minimumHitTarget,
                height: BrowserTabTrailingControlPolicy.minimumHitTarget
            )
            .contentShape(.rect)
    }
}

#Preview {
    SidebarTabTrailingControlLabel(systemName: "xmark")
        .padding()
}
