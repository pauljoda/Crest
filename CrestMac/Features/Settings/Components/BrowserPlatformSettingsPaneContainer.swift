import SwiftUI

/// The native macOS grouped form for a shared settings pane: one centred
/// column of rows.
///
/// On macOS 27 the form spans the whole page, as
/// ``BrowserSettingsPageWideColumn`` describes. On macOS 26 the form is the
/// column itself, placed by ``BrowserSettingsColumnLayout``.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    // MARK: - Variables

    @Environment(\.browserSettingsTabState) private var tabState
    @Environment(\.browserSettingsScrollKey) private var scrollKey
    @Environment(\.browserSettingsColumnWidth) private var columnWidth
    @Environment(\.browserSettingsSectionOwner) private var sections
    @State private var standaloneScroll = BrowserNativeScrollState()
    @State private var scrollTarget: BrowserSettingsSection?
    @State private var madeSections = BrowserSettingsMadeSections()
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    // MARK: - Initializers

    init(
        destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Group {
            if #available(macOS 27, *) {
                form
                    .modifier(BrowserSettingsPageWideColumn(columnWidth: shownColumnWidth))
            } else {
                BrowserSettingsColumnLayout(columnWidth: shownColumnWidth) {
                    form
                }
            }
        }
        .accessibilityIdentifier("settings-form-\(destination.name)")
    }

    private var form: some View {
        ScrollViewReader { proxy in
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .browserNativeScrollState(
                tabState?.scroll(forKey: scrollKey ?? destination.name) ?? standaloneScroll,
                target: scrollTarget?.name, isMade: madeSections.contains(named:)
            )
            .environment(\.browserSettingsMadeSections, madeSections)
            .task(id: tabState?.requestedSection) {
                await reveal(tabState?.requestedSection, with: proxy)
            }
        }
    }

    private var shownColumnWidth: CGFloat {
        columnWidth ?? BrowserSettingsLayout.formColumnWidth
    }

    // MARK: - Actions - Search results

    /// Scrolls to the section a search result or a route asked this page
    /// for. The Mac's grouped form draws no row backgrounds, so the section
    /// isn't marked; it arrives at the top of the page instead.
    private func reveal(_ section: BrowserSettingsSection?, with proxy: ScrollViewProxy) async {
        guard let tabState, let section, sections?.contains(section) ?? false else { return }
        scrollTarget = section
        // The page steps toward the section until the form has made its
        // rows; the form's own reader then finds it by its `id`.
        try? await Task.sleep(for: CrestMotion.searchMatchSettle)
        await madeSections.arrival(of: section)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: CrestMotion.scrollAlignmentTransition)) {
            proxy.scrollTo(section.name, anchor: .top)
        }
        // Let the scroll finish before clearing the request, which restarts
        // this task, then let the page keep its place as it would anywhere.
        try? await Task.sleep(for: .seconds(CrestMotion.scrollAlignmentTransition))
        guard !Task.isCancelled else { return }
        scrollTarget = nil
        tabState.requestedSection = nil
    }
}
