namespace CrestCore.Contracts;

/// <summary>
/// How a Space searches and how long it keeps what it browses. The selected search
/// provider is a built-in engine's identifier or `custom:` and a custom engine's
/// identity; a selection that names no available engine reads as Google.
/// </summary>
public sealed record BrowsingPreferences(
    string SelectedSearchProviderId,
    IReadOnlyList<CustomSearchProvider> CustomSearchProviders,
    bool SearchSuggestionsEnabled,
    CurrentTabCleanup CurrentTabCleanup,
    ContentBlockingPolicy ContentBlocking,
    DataRetentionPreferences DataRetention) {
    #region Actions - Equality

    public bool Equals(BrowsingPreferences? other) => other is not null
        && SelectedSearchProviderId == other.SelectedSearchProviderId
        && CustomSearchProviders.SequenceEqual(other.CustomSearchProviders)
        && SearchSuggestionsEnabled == other.SearchSuggestionsEnabled
        && CurrentTabCleanup == other.CurrentTabCleanup
        && ContentBlocking == other.ContentBlocking
        && DataRetention == other.DataRetention;

    public override int GetHashCode() => HashCode.Combine(SelectedSearchProviderId, CustomSearchProviders.Count,
        SearchSuggestionsEnabled, CurrentTabCleanup, ContentBlocking, DataRetention);

    #endregion
}
