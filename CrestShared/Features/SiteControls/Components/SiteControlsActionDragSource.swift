import SwiftUI

/// Lets the person pick an action up and carry it within Site Controls. A
/// pointer that moves a few points lifts the action `pickUp` names at the
/// point it started from; a finger first holds it a moment, so a swipe still
/// scrolls the list and moves the sheet. Site Controls then draw it as its tile under the pointer, and
/// letting go lands it.
struct SiteControlsActionDragSource: ViewModifier {
    // MARK: - Static Variables

    /// How far a pointer moves before the action lifts, so a sloppy click
    /// still runs it.
    private static let liftDistance: CGFloat = 4
    /// How long a finger holds the action before it lifts.
    private static let holdDuration = 0.3

    // MARK: - Variables

    let model: SiteControlsModel
    /// Whether the view lifts anything; its subviews' own gestures work
    /// either way.
    var isEnabled = true
    /// The drag that starts at a point, in ``SiteControlsModel/space``, with
    /// the pointer now at the second; nil where nothing lifts.
    let pickUp: (_ start: CGPoint, _ location: CGPoint) -> SiteControlsModel.ActionDrag?

    /// Whether the gesture is under way, which falls back when it ends or
    /// is cut off; one cut off before it ends drops what it carried.
    @GestureState private var isDragging = false

    // MARK: - Actions - Drawing

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
            // UIKit's hold, which gives way to a scroll or the sheet's own
            // drag that moves first, and once it holds keeps the finger.
            content.modifier(
                SiteControlsHoldToDrag(isEnabled: isEnabled, holdDuration: Self.holdDuration) { phase, location in
                    switch phase {
                    case .began, .changed: moved(start: location, location: location)
                    case .ended: model.endDrag()
                    case .cancelled: model.cancelDrag()
                    }
                })
        #else
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: Self.liftDistance, coordinateSpace: SiteControlsModel.space)
                        .updating($isDragging) { _, isDragging, _ in isDragging = true }
                        .onChanged { moved(start: $0.startLocation, location: $0.location) }
                        .onEnded { _ in model.endDrag() }, including: isEnabled ? .all : .subviews
                )
                .onChange(of: isDragging) { _, isDragging in
                    // A drag that ended lands first; only one cut off is
                    // still carried a turn later, and only it is dropped.
                    guard !isDragging, let id = model.drag?.id else { return }
                    Task { @MainActor in
                        await Task.yield()
                        model.cancelDrag(id)
                    }
                }
        #endif
    }

    private func moved(start: CGPoint, location: CGPoint) {
        if model.drag != nil {
            model.carry(to: location)
        } else if let drag = pickUp(start, location) {
            model.pickUp(drag)
        }
    }
}

extension View {
    /// Lets the person pick up the action `pickUp` names where a drag starts
    /// and carry it within Site Controls.
    func siteControlsActionDragSource(
        _ model: SiteControlsModel, isEnabled: Bool = true,
        pickUp: @escaping (_ start: CGPoint, _ location: CGPoint) -> SiteControlsModel.ActionDrag?
    ) -> some View {
        modifier(SiteControlsActionDragSource(model: model, isEnabled: isEnabled, pickUp: pickUp))
    }
}

/// The action a drag carries, drawn as its tile where the pointer holds it,
/// lifted off Site Controls, with a remove badge while letting it go would
/// take it off the row.
struct SiteControlsDragPreview: View {
    let model: SiteControlsModel
    let drag: SiteControlsModel.ActionDrag

    var body: some View {
        let removes = model.dragRemoves
        SiteControlsActionTile(item: model.item(drag.action), height: drag.size.height, action: {})
            .frame(width: drag.size.width)
            .background(CrestColor.windowBackground, in: .rect(cornerRadius: CrestRadius.compact))
            .overlay {
                RoundedRectangle(cornerRadius: CrestRadius.compact)
                    .strokeBorder(CrestColor.subtleBorder, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if removes {
                    SiteControlsRemoveBadge()
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .opacity(removes ? 0.8 : 1)
            .crestElevation(.lifted)
            .scaleEffect(1.05)
            .animation(CrestMotion.dragSource, value: removes)
            .position(drag.center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The badge a dragged tile wears while letting it go would take it off the
/// row.
private struct SiteControlsRemoveBadge: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 16, height: 16)
            .background(CrestColor.danger, in: .circle)
            .overlay { Circle().strokeBorder(CrestColor.windowBackground, lineWidth: 1.5) }
    }
}
