import SwiftUI

/// A Space control's glyph at its ideal width wherever there is room. A
/// capsule pressed for room narrows its buttons toward the minimum before
/// any spill past its edge. As a toolbar item it is a plain label the bar
/// draws itself, and lists by its title once it folds into the overflow menu.
struct MobileSpaceUtilityButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement

    var body: some View {
        if controlPlacement.movesControlsToToolbar {
            Label(title, systemImage: systemImage)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(minWidth: 32, idealWidth: 44, maxWidth: 44)
                .frame(height: 44)
                .contentShape(.rect)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        HStack {
            MobileSpaceUtilityButtonLabel(title: "Archive", systemImage: "archivebox")
            MobileSpaceUtilityButtonLabel(title: "Settings", systemImage: "gearshape")
        }.padding()
    }
#endif
