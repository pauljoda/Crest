import SwiftUI

struct SpaceExtensionScopeBanner: View {
    let space: BrowserSpace

    var body: some View {
        Label {
            Text(
                "Extensions here stay on this device and belong only to the \(space.name) Space."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(space.accent.color)
        }
        .accessibilityElement(children: .combine)
    }
}
