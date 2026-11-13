import SwiftUI

/// A folder card's search, drawn as one of the sidebar's tab rows: a row's
/// height and corners, with the magnifier in the favicon's column and the
/// typing where a title sits, in the sidebar's text size. It takes the
/// keyboard once its card has grown, unless a finger held the card open,
/// and Return does what `submit` says.
struct BrowserFolderPreviewSearchField: View {
    // MARK: - Variables

    @Binding var text: String
    let submit: () -> Void

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.browserTabPreviewOpeningTime) private var openingTime
    @Environment(\.browserTabPreviewTakesKeyboard) private var takesKeyboard
    @FocusState private var isFocused: Bool

    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    // MARK: - Actions - Presentation

    var body: some View {
        let metrics = capabilities.tabRowMetrics
        HStack(spacing: metrics.contentSpacing) {
            Label {
                TextField("Search Tabs", text: $text, prompt: Text("Search Tabs"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focused($isFocused)
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
        .task {
            guard takesKeyboard else { return }
            do { try await Task.sleep(for: openingTime) } catch { return }
            isFocused = true
        }
    }

    /// The column a pointer row's favicon takes at the sidebar's text size.
    private var faviconSize: CGFloat {
        TabFaviconMetrics.defaultSize * BrowserSidebarDensity(tabScale).scale
    }
}
