import SwiftUI

/// A Space control's glyph at its ideal width wherever there is room. A
/// capsule pressed for room narrows its buttons toward the minimum before
/// any spill past its edge. As a toolbar item it is a plain label the bar
/// draws itself, and lists by its title once it folds into the overflow menu.
struct MobileSpaceUtilityButtonLabel: View {
    // MARK: - Static Variables

    /// The narrowest a glyph gets in a capsule pressed for room.
    static let narrowestWidth: CGFloat = 32
    /// The design system's chrome surface under each glyph of a capsule,
    /// rounded to the capsule's own ends.
    static let capsuleButtonStyle = CrestChromeButtonStyle(
        controlSize: nil, cornerRadius: CrestLayout.minimumHitTarget / 2)

    // MARK: - Variables

    let title: LocalizedStringKey
    let systemImage: String

    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement

    // MARK: - Actions - Drawing

    var body: some View {
        if controlPlacement.movesControlsToToolbar {
            Label(title, systemImage: systemImage)
        } else {
            Image(systemName: systemImage)
                .font(CrestTypography.touchControlGlyph)
                .frame(
                    minWidth: Self.narrowestWidth, idealWidth: CrestLayout.minimumHitTarget,
                    maxWidth: CrestLayout.minimumHitTarget
                )
                .frame(height: CrestLayout.minimumHitTarget)
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
