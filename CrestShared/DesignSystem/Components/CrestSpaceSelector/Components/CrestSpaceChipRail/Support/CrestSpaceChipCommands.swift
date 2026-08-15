import SwiftUI

struct CrestSpaceChipCommands: ViewModifier {
    let commands: [CrestSpaceChipCommand]

    @ViewBuilder
    func body(content: Content) -> some View {
        if commands.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(commands) { command in
                    Button(
                        command.title,
                        systemImage: command.systemImage,
                        role: command.isDestructive ? .destructive : nil,
                        action: command.perform
                    )
                }
            }
        }
    }
}

#Preview("Space Chip Commands", traits: .sizeThatFitsLayout) {
    Button(CrestSpaceSelectorPreviewFixture.workSpace.name) {}
        .modifier(
            CrestSpaceChipCommands(
                commands: [
                    .rename {},
                    .customize {},
                    .delete {},
                ]
            )
        )
        .padding()
        .environment(\.displayScale, 2)
        .preferredColorScheme(.light)
}
