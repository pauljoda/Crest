import SwiftUI

struct MobileSpaceUtilityButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

#Preview("Space Utility Button Label", traits: .sizeThatFitsLayout) {
    MobileSpaceUtilityButtonLabel(systemImage: "archivebox")
        .padding()
}
