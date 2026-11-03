import SwiftUI

/// The outline of a selectable card: a rounded rectangle, or a circle for the
/// ring around a swatch. Its fill, border, focus ring and hit area all take it.
struct CrestSelectableCardShape: InsettableShape {
    // MARK: - Variables

    /// The corner radius, or nil for a circle.
    let cornerRadius: CGFloat?
    private var insetAmount: CGFloat = 0

    // MARK: - Initializers

    init(cornerRadius: CGFloat?) {
        self.cornerRadius = cornerRadius
    }

    // MARK: - Actions - Drawing

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard let cornerRadius else { return Circle().path(in: inset) }
        return RoundedRectangle(cornerRadius: max(0, cornerRadius - insetAmount), style: .continuous)
            .path(in: inset)
    }

    func inset(by amount: CGFloat) -> CrestSelectableCardShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
