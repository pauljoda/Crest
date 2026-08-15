import SwiftUI

struct SpacePickerIcon: View {
    let space: BrowserSpace
    let size: CGFloat
    let lockSize: CGFloat

    var body: some View {
        BrowserSpaceSymbolArtwork(
            space: space,
            size: size,
            lockSize: lockSize
        )
    }
}

#Preview("Space Picker Icon") {
    SpacePickerIcon(
        space: SpaceSwitcherPreviewFixture.firstSpace,
        size: 24,
        lockSize: 6
    )
    .padding()
}
