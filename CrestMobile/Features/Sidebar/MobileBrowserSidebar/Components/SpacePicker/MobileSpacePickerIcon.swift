import SwiftUI

struct MobileSpacePickerIcon: View {
    let space: BrowserSpace

    var body: some View {
        BrowserSpaceSymbolArtwork(
            space: space,
            size: 30,
            lockSize: 7
        )
        .padding(4)
    }
}

#Preview("Mobile Space Picker Icon", traits: .sizeThatFitsLayout) {
    let fixture = MobileBrowserPreviewFixture()

    MobileSpacePickerIcon(space: fixture.space)
        .padding()
}
