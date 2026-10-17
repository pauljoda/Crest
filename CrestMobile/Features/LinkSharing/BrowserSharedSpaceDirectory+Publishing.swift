import SwiftUI
import UIKit

extension BrowserSharedSpaceDirectory {
    // MARK: - Static Variables

    /// The size the share sheet draws a Space's icon at, in points.
    private static let iconSize: CGFloat = 28

    // MARK: - Actions - Publishing

    /// The directory of the Spaces `browser` holds, in sidebar order, with
    /// the one its window shows marked as the last.
    @MainActor
    init(browser: BrowserStore) {
        self.init(
            spaces: browser.spaceModels.map { space in
                Space(id: space.id, name: space.settings.name, isLocked: space.identity.requiresAuthentication)
            },
            lastSpaceID: browser.shownSpace?.id
        )
    }

    /// Writes the Spaces of `browser` and their icons for the share
    /// extension, which cannot draw a Space without the core. Icons are
    /// drawn every time, since a Space's look can change while its name and
    /// lock stay the same.
    @MainActor
    static func publish(from browser: BrowserStore, to container: BrowserLinkSharingContainer) {
        let directory = BrowserSharedSpaceDirectory(browser: browser)
        var icons: [UUID: Data] = [:]
        for space in browser.spaceModels {
            let renderer = ImageRenderer(content: BrowserSpaceIdentityIcon(space: space, size: iconSize))
            renderer.scale = 3
            icons[space.id] = renderer.uiImage?.pngData()
        }
        try? directory.write(to: container, icons: icons)
    }
}
