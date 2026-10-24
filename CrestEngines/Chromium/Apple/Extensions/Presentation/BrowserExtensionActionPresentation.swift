import AppKit

@MainActor
struct BrowserExtensionActionPresentation: Identifiable {
    let id: String
    let displayName: String
    let badgeText: String
    let icon: NSImage?
    let isEnabled: Bool
    let isPinned: Bool
    let isLoading: Bool

    init(
        id: String,
        displayName: String,
        badgeText: String = "",
        icon: NSImage? = nil,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        isLoading: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.badgeText = badgeText
        self.icon = icon
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.isLoading = isLoading
    }

}

extension BrowserExtensionActionPresentation {
    /// An action as the engine lists it.
    init(_ action: ExtensionAction) {
        self.init(
            id: action.id, displayName: action.name, badgeText: action.badge,
            icon: action.icon.flatMap(NSImage.extensionIcon), isEnabled: action.enabled,
            isPinned: action.pinned)
    }
}

extension NSImage {
    /// Decoded extension icons by their encoded bytes. The engine encodes the
    /// icons again each time it lists a Space's actions, which a badge change
    /// does, so an icon whose bytes did not change reuses its image.
    @MainActor private static var extensionIcons: [Data: NSImage] = [:]
    /// The cached icons' bytes, oldest first. A full cache lets only its
    /// oldest icon go, so the icons a Space keeps showing stay decoded.
    @MainActor private static var extensionIconOrder: [Data] = []
    private static let extensionIconLimit = 256

    /// The image for an extension's encoded icon, decoded once per distinct icon.
    @MainActor static func extensionIcon(_ data: Data) -> NSImage? {
        if let image = extensionIcons[data] { return image }
        guard let image = NSImage(extensionIcon: data) else { return nil }
        if extensionIconOrder.count >= extensionIconLimit {
            extensionIcons[extensionIconOrder.removeFirst()] = nil
        }
        extensionIcons[data] = image
        extensionIconOrder.append(data)
        return image
    }

    /// An extension's icon, which the engine encodes at twice its size in points.
    convenience init?(extensionIcon data: Data) {
        self.init(data: data)
        size = NSSize(width: size.width / 2, height: size.height / 2)
    }
}
