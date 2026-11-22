import SwiftUI

/// The badge a tab wears for the first status its page is in: a disc in the
/// status's color, laid on the device's material as the sidebar's layers
/// are, carrying the status's symbol and pressed like a button or opened like
/// a menu. It hangs off the corner of the tab's favicon, a little larger than
/// the engine badge it stands in for, or fills the favicon's place. The disc
/// answers the pointer, and its hit area reaches past it so it stays easy to
/// press.
struct BrowserTabStatusBadge: View {
    // MARK: - Static Variables

    /// The disc on the favicon's corner, at default density.
    static let diameter: CGFloat = 13

    /// The symbol inside a corner disc.
    static let markSize: CGFloat = 7

    /// How far a corner disc answers a press, around its center.
    static let hitTarget: CGFloat = 18

    // MARK: - Variables

    let mark: BrowserTabStatusMark
    let tab: BrowserTabStatusSource

    /// The disc's diameter, in points; the symbol and the hit area keep their
    /// proportion to it.
    var diameter: CGFloat = BrowserTabStatusBadge.diameter

    @State private var isHovering = false

    var body: some View {
        let symbol = diameter * Self.markSize / Self.diameter
        let hitTarget = diameter * Self.hitTarget / Self.diameter
        BrowserTabStatusControl(mark: mark, tab: tab) {
            Image(systemName: mark.symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(mark.glyph)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: symbol, height: symbol)
                .frame(width: diameter, height: diameter)
                .background {
                    CrestSurfaceLayer(
                        shape: Circle(), tint: mark.tint, hoverTint: isHovering ? CrestColor.hover : nil)
                }
                .onHover { isHovering = $0 }
                .frame(width: hitTarget, height: hitTarget)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}
