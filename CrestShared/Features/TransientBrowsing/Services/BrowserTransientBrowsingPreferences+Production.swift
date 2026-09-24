extension BrowserTransientBrowsingPreferences {
    /// The app's preferences, with the site rule answered by `core`.
    static func production(core: CrestCore) -> BrowserTransientBrowsingPreferences {
        BrowserTransientBrowsingPreferences(
            archiveLifetime: BrowserCorePolicy.quickWindowArchiveLifetime(
                BrowserLinkPreferenceStore.shared.preferences.quickWindowArchivePolicy),
            rememberSpace: { spaceID, url in
                BrowserLinkPreferenceStore.shared.rememberQuickWindowSpace(spaceID, for: url, asking: core)
            }
        )
    }
}
