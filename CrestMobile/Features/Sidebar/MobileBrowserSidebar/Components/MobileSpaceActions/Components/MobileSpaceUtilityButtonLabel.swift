import SwiftUI

/// A Space control's glyph at its ideal width wherever there is room. A
/// capsule pressed for room narrows its buttons toward the minimum before
/// any spill past its edge.
struct MobileSpaceUtilityButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(minWidth: 32, idealWidth: 44, maxWidth: 44)
            .frame(height: 44)
            .contentShape(.rect)
    }
}

#if DEBUG
    #Preview("Component") {
        HStack {
            MobileSpaceUtilityButtonLabel(systemImage: "archivebox")
            MobileSpaceUtilityButtonLabel(systemImage: "gearshape")
        }.padding()
    }
#endif
