import SwiftUI

struct BrowserPeekDestinationControl: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let openInSpace: (BrowserSpaceRuntimeAssignment) -> Void

    private var selectedSpace: BrowserSpace? {
        spaces.first { $0.id == selectedSpaceID }
    }

    private var spaceTint: Color {
        selectedSpace?.branding.backgroundColor.color ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 0) {
            BrowserPeekDestinationPrimaryButton(
                selectedSpace: selectedSpace,
                openInSelectedSpace: openInSelectedSpace
            )

            Rectangle()
                .fill(.primary.opacity(BrowserPeekChromePolicy.separatorOpacity))
                .frame(
                    width: BrowserPeekChromePolicy.separatorWidth,
                    height: BrowserPeekChromePolicy.separatorHeight
                )
                .accessibilityHidden(true)

            BrowserPeekDestinationMenu(
                spaces: spaces,
                selectedSpace: selectedSpace,
                openInSpace: openInSpace
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: BrowserPeekChromePolicy.controlHeight)
        .browserReadableForeground(over: spaceTint)
        .contentShape(.capsule)
        .glassEffect(
            .regular.tint(spaceTint).interactive(),
            in: .capsule
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-space-control")
    }

    private func openInSelectedSpace() {
        guard let selectedSpace else { return }
        openInSpace(BrowserSpaceRuntimeAssignment(space: selectedSpace))
    }
}
