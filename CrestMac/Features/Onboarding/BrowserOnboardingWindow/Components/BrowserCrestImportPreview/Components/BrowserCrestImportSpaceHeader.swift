import SwiftUI

struct BrowserCrestImportSpaceHeader: View {
    let space: BrowserSpace

    var body: some View {
        HStack(spacing: 8) {
            BrowserSpaceIdentityIcon(space: space, size: 22)
            Text(space.name)
                .font(.callout.weight(.semibold))
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .frame(height: 36)
    }
}
