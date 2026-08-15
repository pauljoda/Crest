import SwiftUI

struct SidebarTabRowContent: View {
    let configuration: SidebarTabRowConfiguration
    let interaction: SidebarTabRowInteractionContext

    var body: some View {
        HStack(spacing: 0) {
            SidebarTabActivationContent(
                configuration: configuration,
                isRenaming: interaction.isRenaming,
                draftTitle: interaction.draftTitle,
                isTitleFocused: interaction.isTitleFocused,
                commitTitle: interaction.commitTitle,
                cancelTitleEditing: interaction.cancelTitleEditing
            )
            SidebarTabTrailingControl(
                configuration: configuration,
                isHovering: interaction.isHovering.wrappedValue
            )
            .padding(.trailing, 9)
        }
    }
}

#Preview {
    @Previewable @State var draftTitle = "Example"
    @Previewable @FocusState var isTitleFocused: Bool

    SidebarTabRowContent(
        configuration: SidebarTabRowPreviewFixture.configuration(),
        interaction: SidebarTabRowPreviewFixture.interaction(
            isHovering: .constant(true),
            isDropTargeted: .constant(false),
            draftTitle: $draftTitle,
            isTitleFocused: $isTitleFocused
        )
    )
    .frame(width: 320)
    .padding()
}
