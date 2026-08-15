extension BrowserTransientBrowsingPreferences {
    static var production: BrowserTransientBrowsingPreferences {
        BrowserTransientBrowsingPreferences(
            archiveLifetime: BrowserLinkPreferenceStore.shared.preferences
                .quickWindowArchivePolicy.lifetime,
            rememberSpace: { spaceID, url in
                BrowserLinkPreferenceStore.shared.rememberQuickWindowSpace(
                    spaceID,
                    for: url
                )
            }
        )
    }
}
