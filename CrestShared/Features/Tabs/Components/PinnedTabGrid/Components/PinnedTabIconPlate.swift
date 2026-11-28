import SwiftUI

/// Lays a selected pin's icon on a plate of Crest's surface in the opposite
/// tone where its selection would hide the icon: where none of the colors it
/// is seen in stands apart from what the selection lays under it, as a white
/// icon on the White selection does, or a yellow one on its own yellow tint.
/// A pin at rest, or selected on the bare material, shows its icon as it is.
/// The tile keeps its color; only the icon gains the plate.
struct PinnedTabIconPlate: ViewModifier {
    // MARK: - Static Variables

    /// The least lightness contrast between a color of the icon and its tile
    /// at which the color stands apart: below it the two are nearly one
    /// lightness, as black is on charcoal.
    static let minimumContrast = 1.5
    /// The least perceptual distance between a color of the icon and its
    /// tile at which the color stands apart: below it the two look nearly
    /// the same, as white does on light gray, while a colored icon on its own
    /// paler tint stays apart by its hue.
    static let minimumDistance = 0.15

    // MARK: - Variables

    /// The colors the icon is seen in, or nil while they are unknown or the
    /// pin shows no favicon.
    let palette: BrowserFaviconPalette?
    /// The icon's side.
    let size: CGFloat
    /// How far the plate reaches past the icon on each side.
    let inset: CGFloat

    @Environment(\.browserTabSelectionGround) private var ground

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .background {
                if let scheme = plateScheme {
                    let side = size + 2 * inset
                    RoundedRectangle(cornerRadius: TabFaviconMetrics.cornerRadius(for: side), style: .continuous)
                        .fill(CrestBrandTheme.surface)
                        .frame(width: side, height: side)
                        .environment(\.colorScheme, scheme)
                }
            }
    }

    // MARK: - Actions - Contrast

    /// The scheme of the plate the icon needs, or nil where its selection lays
    /// nothing under it or it reads on what the selection lays. The plate
    /// takes the tone farther from the color the icon is mostly seen in:
    /// charcoal under a light icon, paper under a dark one.
    private var plateScheme: ColorScheme? {
        guard let palette, let ground else { return nil }
        let environment = EnvironmentValues()
        let resolved = ground.resolve(in: environment)
        let tile = BrowserFaviconColor(
            red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        let reads = palette.prominent.contains {
            $0.iconAccent.color.contrastRatio(over: ground, environment: environment) >= Self.minimumContrast
                && $0.perceptualDistance(to: tile) >= Self.minimumDistance
        }
        guard !reads, let main = palette.prominent.first?.iconAccent.color else { return nil }
        let overDark = main.contrastRatio(over: CrestBrandTheme.surfaceDarkComponents.color, environment: environment)
        let overLight = main.contrastRatio(over: CrestBrandTheme.surfaceLightComponents.color, environment: environment)
        return overDark >= overLight ? .dark : .light
    }
}
