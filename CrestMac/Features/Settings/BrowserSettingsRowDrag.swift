import SwiftUI
import UniformTypeIdentifiers

/// Lets a person drag one row of an ordered list in Settings to a new place.
/// A grouped form on the Mac has no reordering of its own, so the row moves
/// live as it passes over another, and the list takes each new order as it
/// forms. What follows the pointer is the row's handle and name alone,
/// without its controls.
struct BrowserSettingsRowDrag<Item: Hashable>: ViewModifier {
    let item: Item
    /// The item's stable name, which the drag carries.
    let name: String
    let title: LocalizedStringResource
    @Binding var dragged: Item?
    /// Moves the item being dragged to where the target stands.
    let move: (Item, Item) -> Void

    /// The row, which starts a drag of the item and takes others dropped over it.
    func body(content: Content) -> some View {
        content
            .onDrag {
                dragged = item
                return NSItemProvider(object: name as NSString)
            } preview: {
                HStack(spacing: CrestSpacing.small) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                    Text(title)
                }
                .padding(.horizontal, CrestSpacing.medium)
                .padding(.vertical, CrestSpacing.small)
                .background {
                    CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.compact, style: .continuous))
                }
            }
            .onDrop(of: [.plainText], delegate: Drop(target: item, dragged: $dragged, move: move))
    }

    /// Moves the dragged row over the row it enters, and lets it go on drop.
    private struct Drop: DropDelegate {
        let target: Item
        @Binding var dragged: Item?
        let move: (Item, Item) -> Void

        /// Moves the dragged row to where the target stands as it enters.
        func dropEntered(info: DropInfo) {
            guard let dragged, dragged != target else { return }
            withAnimation(.snappy(duration: CrestMotion.hoverTransition)) { move(dragged, target) }
        }

        /// Shows the drag as a move.
        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        /// Ends the drag; the row is already in place.
        func performDrop(info: DropInfo) -> Bool {
            dragged = nil
            return true
        }
    }
}
