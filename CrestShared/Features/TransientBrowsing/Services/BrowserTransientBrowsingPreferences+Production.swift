extension BrowserTransientBrowsingPreferences {
    /// The app's preferences, with the site rule answered by `core`.
    static func production(core: CrestCore) -> BrowserTransientBrowsingPreferences {
        BrowserTransientBrowsingPreferences(
            archiveLifetime: BrowserLinkPreferenceStore.shared.preferences.quickWindowArchivePolicy.lifetime,
            rememberSpace: { spaceID, url in
                BrowserLinkPreferenceStore.shared.rememberQuickWindowSpace(spaceID, for: url, asking: core)
            }
        )
    }
}
