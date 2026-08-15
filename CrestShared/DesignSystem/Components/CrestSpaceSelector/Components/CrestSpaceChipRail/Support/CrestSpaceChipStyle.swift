import SwiftUI

/// A Space chip. Exposed because the onboarding wizard's absorbed chip style
/// forwards to it.
struct CrestSpaceChipStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        CrestSpaceChipSurface(
            tint: tint,
            isSelected: isSelected,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
    }
}

#Preview("Space Chip Style", traits: .sizeThatFitsLayout) {
    HStack {
        Button("Work", systemImage: "briefcase.fill") {}
            .buttonStyle(
                CrestSpaceChipStyle(
                    tint: CrestSpaceSelectorPreviewFixture.workSpace.accent.color,
                    isSelected: true
                )
            )

        Button("Private", systemImage: "lock.fill") {}
            .buttonStyle(
                CrestSpaceChipStyle(
                    tint: CrestSpaceSelectorPreviewFixture.privateSpace.accent.color,
                    isSelected: false
                )
            )
    }
    .padding()
    .environment(\.displayScale, 2)
    .preferredColorScheme(.light)
}
