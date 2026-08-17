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
