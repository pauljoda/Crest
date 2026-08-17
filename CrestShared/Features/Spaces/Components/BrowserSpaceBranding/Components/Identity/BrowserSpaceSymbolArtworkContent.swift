import SwiftUI

struct BrowserSpaceSymbolArtworkContent: View {
    let space: BrowserSpace
    let size: CGFloat
    let lockSize: CGFloat

    var body: some View {
        BrowserSpaceIdentityIcon(space: space, size: size)
            .overlay(alignment: .bottomTrailing) {
                if space.accessPolicy.requiresAuthentication {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockSize, weight: .bold))
                        .padding(2)
                        .background(.background, in: .circle)
                }
            }
            .frame(width: size, height: size)
    }
}
