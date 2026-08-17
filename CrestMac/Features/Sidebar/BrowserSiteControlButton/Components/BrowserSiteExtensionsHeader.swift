import SwiftUI

struct BrowserSiteExtensionsHeader: View {
    let manageExtensions: () -> Void

    var body: some View {
        HStack {
            Text("Extensions")
                .font(.headline)
            Spacer(minLength: CrestSpacing.small)
            Button(action: manageExtensions) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(
                        width: BrowserSiteControlLayoutPolicy
                            .manageExtensionControlSize,
                        height: BrowserSiteControlLayoutPolicy
                            .manageExtensionControlSize
                    )
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: .rect(cornerRadius: 6))
            .accessibilityLabel("Manage Extensions")
            .help("Manage Extensions")
        }
    }
}
