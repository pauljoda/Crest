import AppKit

@MainActor
enum BrowserMacAppIconPreference {
    static let defaults = BrowserFolderAppearancePreference.defaults
    private static var restored = false
    private static var appearanceObserver: BrowserMacAppIconAppearanceObserver?

    static func restore() {
        guard !restored else { return }
        restored = true
        appearanceObserver = BrowserMacAppIconAppearanceObserver { refresh() }
        refresh()
    }

    private static func refresh() {
        let name = defaults.string(forKey: BrowserMacAppIconAssets.preferenceKey) ?? ""
        // Clear/Tinted belong to Icon Services. Passing its rasterized preview
        // back as an override loses the Dock's native resolution and treatment.
        NSApp.applicationIconImage =
            BrowserMacAppIconAssets.usesSystemAppearance ? nil : BrowserMacAppIconAssets.image(named: name, in: .main)
    }

    @discardableResult
    static func select(_ name: String) -> Bool {
        let image = BrowserMacAppIconAssets.image(named: name, in: .main)
        guard name.isEmpty || image != nil else { return false }
        defaults.set(name, forKey: BrowserMacAppIconAssets.preferenceKey)
        defaults.synchronize()
        NSApp.applicationIconImage = BrowserMacAppIconAssets.usesSystemAppearance ? nil : image
        let domain =
            Bundle.main.object(forInfoDictionaryKey: BrowserMacAppIconAssets.preferenceDomainKey) as? String
            ?? Bundle.main.bundleIdentifier
        DistributedNotificationCenter.default().postNotificationName(
            BrowserMacAppIconAssets.changedNotification, object: domain, userInfo: nil, deliverImmediately: true)
        return true
    }
}
