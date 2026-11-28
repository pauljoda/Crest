import SwiftUI

/// Draws one section of a settings page under the ``BrowserSettingsSection``
/// that finds it from search.
///
/// ``BrowserSettingsPane`` takes nothing but slots, so a section can't reach a
/// page without naming the words that find it. The slot draws its content as
/// it comes and anchors it for a search result to scroll to.
struct BrowserSettingsSectionSlot<Content: View>: View {
    // MARK: - Variables

    @Environment(\.browserSettingsSectionOwner) private var owner
    @Environment(\.browserSettingsMadeSections) private var madeSections
    let section: BrowserSettingsSection
    /// Whether a search result scrolls here. A section drawn twice on one
    /// page, as Appearance's More Customization does, anchors only once.
    let anchors: Bool
    @ViewBuilder let content: Content

    // MARK: - Initializers

    init(_ section: BrowserSettingsSection, anchors: Bool = true, @ViewBuilder content: () -> Content) {
        self.section = section
        self.anchors = anchors
        self.content = content()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        // A section drawn on a page that doesn't list it would be missing
        // from that page's search.
        assert(
            owner?.contains(section) ?? true,
            "Settings section \(section.name) is drawn on a page that doesn't list it")
        return anchored
    }

    /// The content with only modifiers a form passes through to each row of
    /// its sections. Anything that wraps the content, such as a background or
    /// a geometry reader, turns a section into one plain row, which loses its
    /// card and lays its heading out like a row's content.
    @ViewBuilder private var anchored: some View {
        if anchors {
            content
                .id(section.name)
                // A list makes rows only near the screen; the page steps
                // toward a section until its rows are made.
                .onAppear { madeSections?.rowAppeared(in: section) }
                .onDisappear { madeSections?.rowDisappeared(in: section) }
        } else {
            content
        }
    }
}

/// Which sections of a settings page its list has made rows for, so a search
/// result knows when the section it opens at can be scrolled to. Kept off the
/// view graph: rows come and go as the page scrolls, and none of that should
/// redraw the page.
@MainActor
final class BrowserSettingsMadeSections {
    private var rowCounts: [BrowserSettingsSection: Int] = [:]

    func contains(_ section: BrowserSettingsSection) -> Bool {
        (rowCounts[section] ?? 0) > 0
    }

    /// Whether the list has made rows for the section named `name`, the `id`
    /// its slot anchors it by.
    func contains(named name: String) -> Bool {
        rowCounts.contains { $0.key.name == name && $0.value > 0 }
    }

    /// Waits until the list has made `section`'s rows, or a few seconds pass
    /// on a page that never does.
    func arrival(of section: BrowserSettingsSection) async {
        let deadline = ContinuousClock.now + .seconds(4)
        while !contains(section), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    func rowAppeared(in section: BrowserSettingsSection) {
        rowCounts[section, default: 0] += 1
    }

    func rowDisappeared(in section: BrowserSettingsSection) {
        rowCounts[section] = max(0, (rowCounts[section] ?? 0) - 1)
    }
}

/// A run of settings sections built like a page's, for a part of a page that
/// is drawn in more than one place or behind a condition of its own.
struct BrowserSettingsSectionList<Content: View>: View {
    let content: Content

    init(@BrowserSettingsSectionsBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

/// What a settings page says about itself rather than a setting it offers:
/// a locked Space's way in, an error, a note on sharing, the switch between
/// a page's kinds. It never holds a setting, which belongs in a
/// ``BrowserSettingsSectionSlot`` so search can find it.
struct BrowserSettingsPaneNote<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

/// Builds a settings page out of ``BrowserSettingsSectionSlot``s,
/// ``BrowserSettingsSectionList``s, views whose body is one of those, and
/// ``BrowserSettingsPaneNote``s, with `if`, `if let`, `switch` and `#if`
/// around them.
@MainActor @resultBuilder
enum BrowserSettingsSectionsBuilder {
    static func buildExpression<Content: View>(
        _ slot: BrowserSettingsSectionSlot<Content>
    ) -> BrowserSettingsSectionSlot<Content> {
        slot
    }

    static func buildExpression<Content: View>(
        _ list: BrowserSettingsSectionList<Content>
    ) -> BrowserSettingsSectionList<Content> {
        list
    }

    static func buildExpression<Content: View>(
        _ note: BrowserSettingsPaneNote<Content>
    ) -> BrowserSettingsPaneNote<Content> {
        note
    }

    /// A section view of its own whose body is a slot.
    static func buildExpression<Sections: View, Content: View>(
        _ sections: Sections
    ) -> Sections where Sections.Body == BrowserSettingsSectionSlot<Content> {
        sections
    }

    /// A view of its own that draws a run of sections.
    static func buildExpression<Sections: View, Content: View>(
        _ sections: Sections
    ) -> Sections where Sections.Body == BrowserSettingsSectionList<Content> {
        sections
    }

    static func buildBlock() -> EmptyView {
        EmptyView()
    }

    static func buildPartialBlock<Content: View>(first: Content) -> Content {
        first
    }

    static func buildPartialBlock<Earlier: View, Next: View>(
        accumulated: Earlier, next: Next
    ) -> BrowserSettingsSectionRun<Earlier, Next> {
        BrowserSettingsSectionRun(earlier: accumulated, next: next)
    }

    static func buildOptional<Content: View>(_ content: Content?) -> Content? {
        content
    }

    static func buildEither<First: View, Second: View>(
        first: First
    ) -> BrowserSettingsSectionChoice<First, Second> {
        .first(first)
    }

    static func buildEither<First: View, Second: View>(
        second: Second
    ) -> BrowserSettingsSectionChoice<First, Second> {
        .second(second)
    }
}

/// Sections one after another, as a page's builder strings them together.
struct BrowserSettingsSectionRun<Earlier: View, Next: View>: View {
    let earlier: Earlier
    let next: Next

    var body: some View {
        earlier
        next
    }
}

/// One of two runs of sections, for an `if`–`else` or `switch` in a page.
enum BrowserSettingsSectionChoice<First: View, Second: View>: View {
    case first(First)
    case second(Second)

    var body: some View {
        switch self {
        case .first(let content): content
        case .second(let content): content
        }
    }
}

private struct BrowserSettingsSectionOwnerKey: EnvironmentKey {
    static let defaultValue: [BrowserSettingsSection]? = nil
}

private struct BrowserSettingsMadeSectionsKey: EnvironmentKey {
    static let defaultValue: BrowserSettingsMadeSections? = nil
}

private struct BrowserSettingsSectionRequestKey: EnvironmentKey {
    static let defaultValue: Binding<BrowserSettingsSection?>? = nil
}

extension EnvironmentValues {
    /// The sections of the page being drawn: its destination's, or those of
    /// the Space page that shows a destination's pane for one Space.
    var browserSettingsSectionOwner: [BrowserSettingsSection]? {
        get { self[BrowserSettingsSectionOwnerKey.self] }
        set { self[BrowserSettingsSectionOwnerKey.self] = newValue }
    }

    /// Where the page's slots report the rows its list has made.
    var browserSettingsMadeSections: BrowserSettingsMadeSections? {
        get { self[BrowserSettingsMadeSectionsKey.self] }
        set { self[BrowserSettingsMadeSectionsKey.self] = newValue }
    }

    /// The section a touch shell's search result asks the page it opens to
    /// scroll to, which the page clears once it gets there. The Mac keeps its
    /// request on its Settings tab instead.
    var browserSettingsSectionRequest: Binding<BrowserSettingsSection?>? {
        get { self[BrowserSettingsSectionRequestKey.self] }
        set { self[BrowserSettingsSectionRequestKey.self] = newValue }
    }
}
