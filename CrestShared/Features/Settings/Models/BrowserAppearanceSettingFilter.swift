import SwiftUI

/// Which rows of Settings › Appearance a part of the page shows: the rows the
/// page keeps, or, in More Customization at its end, the rest.
struct BrowserAppearanceSettingFilter: Sendable {
    // MARK: - Static Variables

    /// Every row, where nothing waits in More Customization.
    static let everything = BrowserAppearanceSettingFilter(showsPage: true, showsMore: true)
    /// The rows the page keeps.
    static let page = BrowserAppearanceSettingFilter(showsPage: true, showsMore: false)
    /// The rows More Customization holds.
    static let more = BrowserAppearanceSettingFilter(showsPage: false, showsMore: true)

    // MARK: - Variables

    private let showsPage: Bool
    private let showsMore: Bool

    // MARK: - Initializers

    private init(showsPage: Bool, showsMore: Bool) {
        self.showsPage = showsPage
        self.showsMore = showsMore
    }

    /// Whether this is More Customization, holding only the rows the page
    /// leaves out.
    var isMore: Bool { showsMore && !showsPage }

    // MARK: - Actions - Filtering

    /// Whether this part of the page shows `setting`.
    func shows(_ setting: BrowserAppearanceSetting) -> Bool {
        setting.isOnPage ? showsPage : showsMore
    }

    /// The resettable settings of the rows this part of the page shows, in
    /// order, which a group's Reset puts back and which say whether the group
    /// shows at all.
    func settings(_ rows: [(BrowserAppearanceSetting, CrestResettableSetting)]) -> [CrestResettableSetting] {
        rows.filter { shows($0.0) }.map(\.1)
    }
}

extension EnvironmentValues {
    @Entry var browserAppearanceSettingFilter = BrowserAppearanceSettingFilter.everything
}

extension View {
    /// Shows this Appearance row only where the page's filter keeps
    /// `setting`.
    func browserAppearanceSetting(_ setting: BrowserAppearanceSetting) -> some View {
        modifier(BrowserAppearanceSettingVisibility(setting: setting))
    }
}

private struct BrowserAppearanceSettingVisibility: ViewModifier {
    let setting: BrowserAppearanceSetting
    @Environment(\.browserAppearanceSettingFilter) private var filter

    func body(content: Content) -> some View {
        if filter.shows(setting) {
            content
        }
    }
}
