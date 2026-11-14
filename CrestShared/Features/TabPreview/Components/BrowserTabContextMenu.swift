import SwiftUI

/// A tab's menu, as its sidebar row or pinned tile offers it. Where a finger
/// holds the tab and tab previews are on, the menu shows the tab's card above
/// it, with the last picture Crest took of its page, as the system shows a
/// link's page above its menu. Anywhere else it is the menu alone.
struct BrowserTabContextMenu<MenuItems: View>: ViewModifier {
    // MARK: - Static Variables

    /// How wide the card above a held tab's menu is.
    private static var previewWidth: CGFloat { 320 }

    // MARK: - Variables

    let tab: TabStateModel
    let context: BrowserSidebarListContext?
    let capabilities: BrowserInteractionCapabilities
    /// Whether the tab offers a menu at all.
    let isEnabled: Bool
    @ViewBuilder let menuItems: () -> MenuItems

    @Environment(\.browserTabPictures) private var pictures

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        if isEnabled, capabilities.supportsTouch, BrowserDeviceAppearanceStore.shared.previewsTabsOnHover,
            let pictures, let context
        {
            content.contextMenu(menuItems: menuItems) {
                BrowserTabMenuPreview(tab: tab, context: context, pictures: pictures)
                    .environment(\.browserTabPreviewCardWidth, Self.previewWidth)
            }
        } else {
            content.contextMenu {
                if isEnabled { menuItems() }
            }
        }
    }
}

/// The card above a held tab's menu. It reads the tab's picture in its own
/// body, where only a menu that shows draws it, so a new picture redraws that
/// menu's card rather than every row that offers one.
private struct BrowserTabMenuPreview: View {
    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let pictures: BrowserTabPictures

    var body: some View {
        BrowserTabPreviewCard(tab: tab, context: context, picture: pictures.previewPicture(of: tab.id), floats: false)
    }
}

extension EnvironmentValues {
    /// The pictures the window keeps of its tabs, which a held tab's menu
    /// shows above it, where the shell offers them.
    @Entry var browserTabPictures: BrowserTabPictures?
}
