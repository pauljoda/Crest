import SwiftUI
import UIKit

/// Where a Peek's link menu opens: a clear control under the spot the card
/// shrinks to, so the system's menu appears beneath the card as it does
/// beneath a link's preview. UIKit grows a control's menu up from its bottom
/// edge, so the control spans the room the menu takes.
struct MobilePeekLinkMenuAnchor: UIViewRepresentable {
    // MARK: - Static Variables

    /// The width the system gives a menu like this one.
    private static let menuWidth: CGFloat = 250
    /// The menu's margins and icon column beside each title.
    private static let titleInset: CGFloat = 78
    /// A one-line row, before the person's text size.
    private static let rowHeight: CGFloat = 44
    /// The menu's padding above its first row and below its last.
    private static let menuPadding: CGFloat = 16
    /// How far inside the control's bottom edge the system ends its menu.
    private static let bottomInset: CGFloat = 20

    /// The room the system's menu takes for `items` at the person's text
    /// size, with a title too long for one line, as Download Linked File can
    /// be, on two, and the inset the system keeps below it.
    static func size(for items: [BrowserPeekLinkMenuItem]) -> CGSize {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let row = UIFontMetrics(forTextStyle: .body).scaledValue(for: rowHeight)
        let titleWidth = menuWidth - titleInset
        let height = items.reduce(menuPadding + bottomInset) { height, item in
            let width = (item.title as NSString).size(withAttributes: [.font: font]).width
            let lines = max(1, (width / titleWidth).rounded(.up))
            return height + row + font.lineHeight * (lines - 1)
        }
        return CGSize(width: menuWidth, height: height)
    }

    // MARK: - Variables

    let presentation: BrowserPeekLinkMenuPresentation

    // MARK: - Actions - Hosting

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.showsMenuAsPrimaryAction = true
        anchor.preferredMenuElementOrder = .fixed
        anchor.isAccessibilityElement = false
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        anchor.menu = UIMenu(
            children: presentation.menu.items.map { item in
                UIAction(title: item.title, image: UIImage(systemName: item.systemImage)) { _ in item.perform() }
            })
        anchor.didEnd = presentation.didEnd
        guard context.coordinator.request != presentation.request else { return }
        context.coordinator.request = presentation.request
        // Opens once SwiftUI has committed the control's place.
        DispatchQueue.main.async { anchor.performPrimaryAction() }
    }

    /// The request the menu last opened for.
    final class Coordinator {
        var request = 0
    }

    /// The control the menu opens from, which says when it starts to close.
    final class Anchor: UIButton {
        var didEnd: () -> Void = {}

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            didEnd()
        }
    }
}
