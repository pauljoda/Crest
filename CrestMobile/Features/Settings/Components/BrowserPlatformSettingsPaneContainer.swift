import SwiftUI

/// The native mobile form container for a shared settings pane. The
/// navigation bar carries the page's name in both layouts.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    // MARK: - Variables

    @Environment(\.browserSettingsSectionRequest) private var request
    @Environment(\.browserSettingsSectionOwner) private var sections
    @State private var scrollTarget: BrowserSettingsSection?
    @State private var madeSections = BrowserSettingsMadeSections()
    /// The form starts at its top each time it opens, as it always has; this
    /// only carries a search result's scroll.
    @State private var scroll = BrowserNativeScrollState()
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
        ScrollViewReader { proxy in
            Form {
                content
            }
            .browserNativeScrollState(scroll, target: scrollTarget?.name, isMade: madeSections.contains(named:))
            .environment(\.browserSettingsMadeSections, madeSections)
            .task(id: request?.wrappedValue) {
                await reveal(request?.wrappedValue, with: proxy)
            }
        }
        .accessibilityIdentifier(BrowserMobileAccessibilityID.settingsForm(destination))
    }

    // MARK: - Actions - Search results

    /// Scrolls to the section a section row opened this page for, as the Mac
    /// does: the section arrives at the top of the page, unmarked.
    private func reveal(_ section: BrowserSettingsSection?, with proxy: ScrollViewProxy) async {
        guard let request, let section, sections?.contains(section) ?? false else { return }
        scrollTarget = section
        // The page steps toward the section until the list has made its
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
        request.wrappedValue = nil
    }
}
