import SwiftUI

/// A folder card's search, drawn as one of the sidebar's tab rows: a row's
/// height and corners, with the magnifier in the favicon's column and the
/// typing where a title sits, in the sidebar's text size. Its card decides
/// when it takes the keyboard, and Return does what `submit` says.
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
        let metrics = capabilities.tabRowMetrics
        HStack(spacing: metrics.contentSpacing) {
            Label {
                TextField("Search Tabs", text: $text, prompt: Text("Search Tabs"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .onSubmit(submit)
            } icon: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.faviconSlot?.width ?? faviconSize)
                    .accessibilityHidden(true)
            }
            .padding(.leading, metrics.contentLeadingInset)
            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, metrics.contentTrailingInset)
            }
        }
        .modifier(BrowserSidebarDensityFont(scale: tabScale, supportsTouch: capabilities.supportsTouch))
        .frame(
            maxWidth: .infinity,
            minHeight: capabilities.tabRowHeight(tabScale: tabScale, dynamicTypeSize: dynamicTypeSize),
            alignment: .leading
        )
        .background(.quaternary, in: .rect(cornerRadius: BrowserSidebarMetrics.layerCornerRadius()))
        .accessibilityIdentifier("folder-preview-search")
    }

    /// The column a pointer row's favicon takes at the sidebar's text size.
    private var faviconSize: CGFloat {
        TabFaviconMetrics.defaultSize * BrowserSidebarDensity(tabScale).scale
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
