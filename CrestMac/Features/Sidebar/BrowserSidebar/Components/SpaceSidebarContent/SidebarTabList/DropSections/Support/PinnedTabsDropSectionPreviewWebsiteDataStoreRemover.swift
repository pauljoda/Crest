struct PinnedTabsDropSectionPreviewWebsiteDataStoreRemover:
    BrowserWebsiteDataStoreRemoving
{
    func removePersistentDataStore(
        for profile: BrowsingProfile
    ) async throws {}
}
