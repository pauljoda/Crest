import Foundation

/// Choosing the customization style Spaces show, which gives each Space it
/// reaches that style's look through the core.
extension BrowserStore {
    // MARK: - Mutators

    /// Gives every Space that follows the shared style `style`, each in its
    /// look for that style.
    func chooseCustomizationStyle(
        _ style: BrowserCustomizationStyle, appearance: BrowserDeviceAppearanceStore = .shared
    ) {
        let previous = appearance.customizationStyle
        let browser = profileSettingsBrowser
        let following = browser.availableSpaces.filter { !appearance.hasOwnCustomizationStyle($0.id) }
        appearance.customizationStyle = style
        for space in following {
            browser.restyle(space, from: previous, to: style, appearance: appearance)
        }
    }

    /// Makes `style` the shared style without restyling, as setup does once
    /// the core has given its own Spaces the style's look. A Space that wears
    /// another look keeps it, as a style of its own: the style it showed.
    func adoptCustomizationStyle(
        _ style: BrowserCustomizationStyle, appearance: BrowserDeviceAppearanceStore = .shared
    ) {
        let previous = appearance.customizationStyle
        let keeping = profileSettingsBrowser.availableSpaces.filter { space in
            !appearance.hasOwnCustomizationStyle(space.id) && !style.wears(space.settings.look)
        }
        appearance.customizationStyle = style
        for space in keeping {
            appearance.setCustomizationStyle(previous, for: space.id)
        }
    }

    /// Moves `space` from the look it wears in `previous` to its look in
    /// `style`.
    func restyle(
        _ space: SpaceModel, from previous: BrowserCustomizationStyle, to style: BrowserCustomizationStyle,
        appearance: BrowserDeviceAppearanceStore
    ) {
        let current = space.settings.look
        let next = appearance.look(of: space.id, wearing: current, movingFrom: previous, to: style)
        if next != current { updateSpaceBranding(next, in: space.id) }
    }
}
