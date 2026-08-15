import SwiftUI

struct BrowserCrestImportSpaceSwitcher: View {
    let space: BrowserSpace

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Spacer()
                Image(systemName: "archivebox")
            }
            .foregroundStyle(.secondary)

            BrowserSpaceSymbolArtwork(space: space, size: 23, lockSize: 6)
                .padding(4)
                .background(.primary.opacity(0.08), in: .rect(cornerRadius: 7))
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(.ultraThinMaterial)
    }
}

#Preview("Crest Import Space Switcher") {
    BrowserCrestImportSpaceSwitcher(space: BrowserImportPreviewFixture.sourceSpace)
        .frame(width: 340)
        .padding()
}
