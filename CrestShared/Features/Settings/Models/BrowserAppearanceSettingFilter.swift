import SwiftUI

/// Which rows of Settings › Appearance a part of the page shows: the rows the
/// customization style keeps on the page, or, in Advanced at its end, the
/// rows the style leaves out.
struct BrowserAppearanceSettingFilter: Sendable {
    // MARK: - Static Variables

    /// Every row, as the Heraldic style keeps them.
    static let everything = BrowserAppearanceSettingFilter(style: .heraldic, isAdvanced: false)

    // MARK: - Variables

    let style: BrowserCustomizationStyle
    /// Whether this part of the page is Advanced, which shows the rows the
    /// style leaves out.
    let isAdvanced: Bool

    // MARK: - Actions - Filtering

    /// Whether this part of the page shows `setting`.
    func shows(_ setting: BrowserAppearanceSetting) -> Bool {
        style.shows(setting) != isAdvanced
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
