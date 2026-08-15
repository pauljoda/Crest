import SwiftUI

struct SidebarTabActivationContent: View {
    let configuration: SidebarTabRowConfiguration
    let isRenaming: Bool
    @Binding var draftTitle: String
    var isTitleFocused: FocusState<Bool>.Binding
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void

    @ViewBuilder
    var body: some View {
        if isRenaming {
            SidebarTabRenameField(
                configuration: configuration,
                draftTitle: $draftTitle,
                isTitleFocused: isTitleFocused,
                commitTitle: commitTitle,
                cancelTitleEditing: cancelTitleEditing
            )
        } else {
            SidebarTabActivationButton(configuration: configuration)
        }
    }
}

#Preview {
    @Previewable @State var draftTitle = "Example"
    @Previewable @FocusState var isTitleFocused: Bool

    SidebarTabActivationContent(
        configuration: SidebarTabRowPreviewFixture.configuration(),
        isRenaming: true,
        draftTitle: $draftTitle,
        isTitleFocused: $isTitleFocused,
        commitTitle: {},
        cancelTitleEditing: {}
    )
    .frame(width: 280)
    .padding()
}
