import SwiftUI

struct SidebarTabRenameField: View {
    let configuration: SidebarTabRowConfiguration
    @Binding var draftTitle: String
    var isTitleFocused: FocusState<Bool>.Binding
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void

    var body: some View {
        Label {
            TextField("Tab Name", text: $draftTitle)
                .textFieldStyle(.plain)
                .focused(isTitleFocused)
                .onSubmit(commitTitle)
                .onExitCommand(perform: cancelTitleEditing)
                .accessibilityIdentifier("tab-rename-field")
        } icon: {
            TabFaviconView(
                tab: configuration.tab,
                profileID: configuration.profileID
            )
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var draftTitle = "Example"
    @Previewable @FocusState var isTitleFocused: Bool

    SidebarTabRenameField(
        configuration: SidebarTabRowPreviewFixture.configuration(),
        draftTitle: $draftTitle,
        isTitleFocused: $isTitleFocused,
        commitTitle: {},
        cancelTitleEditing: {}
    )
    .frame(width: 280, height: CrestLayout.sidebarRowHeight)
    .padding()
}
