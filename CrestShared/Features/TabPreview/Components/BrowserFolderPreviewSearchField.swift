import SwiftUI

/// A folder card's search, as tall as one of the sidebar's tab rows and in
/// the sidebar's text size. Its card decides when it takes the keyboard, and
/// Return does what `submit` says.
struct BrowserFolderPreviewSearchField: View {
    // MARK: - Variables

    @Binding var text: String
    /// Whether the field has the keyboard, which its card sets.
    let isFocused: FocusState<Bool>.Binding
    let submit: () -> Void

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    // MARK: - Actions - Presentation

    var body: some View {
        CrestSearchField(
            "Search Tabs", text: $text, isFocused: isFocused,
            height: capabilities.tabRowHeight(tabScale: tabScale, dynamicTypeSize: dynamicTypeSize)
        )
        .onSubmit(submit)
        .modifier(BrowserSidebarDensityFont(scale: tabScale, supportsTouch: capabilities.supportsTouch))
        .accessibilityIdentifier("folder-preview-search")
    }
}

#if DEBUG
    #Preview("Folder card search") {
        @Previewable @State var query = ""
        @Previewable @FocusState var isFocused: Bool
        BrowserFolderPreviewSearchField(text: $query, isFocused: $isFocused) {}
            .frame(width: 264)
            .padding()
    }
#endif
