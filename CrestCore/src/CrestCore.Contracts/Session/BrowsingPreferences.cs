namespace CrestCore.Contracts;

/// <summary>
/// How a Space searches and how long it keeps what it browses. The Space
/// searches with a built-in engine or with one of its custom engines, and
/// exactly one of <see cref="SelectedBuiltInEngine"/> and
/// <see cref="SelectedCustomEngineId"/> names it; a custom selection that names
/// no usable engine reads as Google.
/// </summary>
public sealed record BrowsingPreferences(
    BuiltInSearchEngine? SelectedBuiltInEngine,
    Guid? SelectedCustomEngineId,
    IReadOnlyList<CustomSearchProvider> CustomSearchProviders,
    bool SearchSuggestionsEnabled,
    CurrentTabCleanup CurrentTabCleanup,
    ContentBlockingPolicy ContentBlocking,
    DataRetentionPreferences DataRetention) {
    #region Actions - Equality

    public bool Equals(BrowsingPreferences? other) => other is not null
        && SelectedBuiltInEngine == other.SelectedBuiltInEngine
        && SelectedCustomEngineId == other.SelectedCustomEngineId
        && CustomSearchProviders.SequenceEqual(other.CustomSearchProviders)
        && SearchSuggestionsEnabled == other.SearchSuggestionsEnabled
        && CurrentTabCleanup == other.CurrentTabCleanup
        && ContentBlocking == other.ContentBlocking
        && DataRetention == other.DataRetention;

    public override int GetHashCode() => HashCode.Combine(SelectedBuiltInEngine, SelectedCustomEngineId, CustomSearchProviders.Count,
        SearchSuggestionsEnabled, CurrentTabCleanup, ContentBlocking, DataRetention);

    #endregion
}
