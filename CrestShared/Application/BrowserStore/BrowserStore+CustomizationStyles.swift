import Foundation

// MARK: - Types

/// The look a Space wore before a style restyled it, and the look it wears
/// now.
struct BrowserSpaceRestyle: Equatable {
    let from: SpaceBranding
    let to: SpaceBranding
}

/// Choosing the customization style Spaces show, which gives each Space it
/// reaches that style's look through the core.
extension BrowserStore {
    // MARK: - Mutators

    /// Gives every Space that follows the shared style `style`, each in its
    /// look for that style, and answers each restyled Space's looks by Space.
    /// Settings and setup's look both choose it here.
    @discardableResult
    func chooseCustomizationStyle(
        _ style: BrowserCustomizationStyle, appearance: BrowserDeviceAppearanceStore = .shared
    ) -> [UUID: BrowserSpaceRestyle] {
        let previous = appearance.customizationStyle
        let browser = profileSettingsBrowser
        let following = browser.availableSpaces.filter { !appearance.hasOwnCustomizationStyle($0.id) }
        appearance.customizationStyle = style
        var restyled: [UUID: BrowserSpaceRestyle] = [:]
        for space in following {
            restyled[space.id] = browser.restyle(space, from: previous, to: style, appearance: appearance)
        }
        return restyled
    }

    /// Moves `space` from the look it wears in `previous` to its look in
    /// `style`, answering both looks when they differ.
    @discardableResult
    func restyle(
        _ space: SpaceModel, from previous: BrowserCustomizationStyle, to style: BrowserCustomizationStyle,
        appearance: BrowserDeviceAppearanceStore
    ) -> BrowserSpaceRestyle? {
        let current = space.settings.look
        let next = appearance.look(of: space.id, wearing: current, movingFrom: previous, to: style)
        guard next != current else { return nil }
        updateSpaceBranding(next, in: space.id)
        return BrowserSpaceRestyle(from: current, to: next)
    }
}
