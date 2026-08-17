import SwiftUI

struct BrowserSpaceIdentityLabel: View {
    let space: BrowserSpace
    var title: String?
    var iconSize: CGFloat = 20

    init(space: BrowserSpace, title: String? = nil, iconSize: CGFloat = 20) {
        self.space = space
        self.title = title
        self.iconSize = iconSize
    }

    var body: some View {
        Label {
            Text(title ?? space.name)
        } icon: {
            BrowserSpaceSymbolArtwork(
                space: space,
                size: iconSize,
                lockSize: max(5, iconSize * 0.24)
            )
            .frame(width: iconSize, height: iconSize)
        }
    }
}
