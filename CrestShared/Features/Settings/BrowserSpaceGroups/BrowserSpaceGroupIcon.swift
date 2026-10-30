import SwiftUI

/// A group's crest in a list of Spaces: its primary's crest, with the crests
/// of up to two Sub-Spaces stacked behind it.
struct BrowserSpaceGroupIcon: View {
    let members: [SpaceModel]
    var size: CGFloat = 18

    var body: some View {
        let behind = Array(members.dropFirst().prefix(BrowserSpaceGroupIconMetrics.stackedCount))
        ZStack(alignment: .leading) {
            ForEach(Array(behind.enumerated().reversed()), id: \.element.id) { index, member in
                BrowserSpaceIdentityIcon(space: member, size: size * BrowserSpaceGroupIconMetrics.stackedScale)
                    .opacity(BrowserSpaceGroupIconMetrics.stackedOpacity)
                    .offset(x: CGFloat(index + 1) * BrowserSpaceGroupIconMetrics.stackOffset)
            }
            if let primary = members.first {
                BrowserSpaceIdentityIcon(space: primary, size: size)
            }
        }
        .frame(
            width: size + CGFloat(behind.count) * BrowserSpaceGroupIconMetrics.stackOffset, height: size,
            alignment: .leading
        )
        .accessibilityHidden(true)
    }
}

private enum BrowserSpaceGroupIconMetrics {
    static let stackedCount = 2
    static let stackOffset: CGFloat = 6
    static let stackedScale: CGFloat = 0.85
    static let stackedOpacity = 0.75
}
