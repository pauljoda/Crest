extension BrowserTransientBrowsingPreferences {
    static var production: BrowserTransientBrowsingPreferences {
        BrowserTransientBrowsingPreferences(
            archiveLifetime: BrowserCorePolicy.quickWindowArchiveLifetime(
                BrowserLinkPreferenceStore.shared.preferences.quickWindowArchivePolicy),
            rememberSpace: { spaceID, url in
                BrowserLinkPreferenceStore.shared.rememberQuickWindowSpace(
                    spaceID,
                    for: url
                )
            }
        )
    }
}
