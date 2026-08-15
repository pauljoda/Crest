import SwiftUI

/// The dashed "one more" chip.
struct CrestSpaceAddChipStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        CrestSpaceAddChipSurface(
            tint: tint,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
    }
}

#Preview("Add Space Chip Style", traits: .sizeThatFitsLayout) {
    Button("New Space", systemImage: "plus") {}
        .buttonStyle(
            CrestSpaceAddChipStyle(
                tint: CrestSpaceSelectorPreviewFixture.workSpace.accent.color
            )
        )
        .padding()
        .environment(\.displayScale, 2)
        .preferredColorScheme(.light)
}
