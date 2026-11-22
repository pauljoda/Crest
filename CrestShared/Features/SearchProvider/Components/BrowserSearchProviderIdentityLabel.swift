import SwiftUI

/// How large a search provider's icon and name sit, by input size.
struct BrowserSearchProviderIdentityLabelLayout: Hashable, Sendable {
    // MARK: - Static Variables

    static let compact = BrowserSearchProviderIdentityLabelLayout(
        name: "compact", iconSize: 20, iconTrailingRoom: 0, verticalPadding: 0)
    /// A touch screen's picker draws its value as the icon's image against
    /// the name, so the image itself carries the room between them.
    static let touch = BrowserSearchProviderIdentityLabelLayout(
        name: "touch", iconSize: 20, iconTrailingRoom: 8, verticalPadding: 4)

    #if os(macOS)
        static let platformDefault = compact
    #else
        static let platformDefault = touch
    #endif

    // MARK: - Variables

    let name: String
    let iconSize: CGFloat
    /// Clear room drawn into the icon's image after the icon.
    let iconTrailingRoom: CGFloat
    let verticalPadding: CGFloat

    // MARK: - Initializers

    private init(name: String, iconSize: CGFloat, iconTrailingRoom: CGFloat, verticalPadding: CGFloat) {
        self.name = name
        self.iconSize = iconSize
        self.iconTrailingRoom = iconTrailingRoom
        self.verticalPadding = verticalPadding
    }

    // MARK: - Actions - Identity

    static func == (
        lhs: BrowserSearchProviderIdentityLabelLayout, rhs: BrowserSearchProviderIdentityLabelLayout
    ) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// A search provider's icon and name, as a label. A picker's menu draws a
/// label as its icon's image and its text with nothing between, so on a
/// touch screen the image carries the room after the icon.
struct BrowserSearchProviderIdentityLabel: View {
    let provider: SearchProvider
    var profileID: UUID? = nil
    var title: String? = nil
    var layout: BrowserSearchProviderIdentityLabelLayout = .platformDefault

    var body: some View {
        Label {
            Text(title ?? provider.title)
        } icon: {
            BrowserSearchProviderIcon(
                provider: provider,
                profileID: profileID,
                size: layout.iconSize,
                trailingRoom: layout.iconTrailingRoom
            )
        }
        .labelStyle(.titleAndIcon)
        .padding(.vertical, layout.verticalPadding)
    }
}
