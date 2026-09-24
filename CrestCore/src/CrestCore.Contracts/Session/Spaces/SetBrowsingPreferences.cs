namespace CrestCore.Contracts;

/// Sets whether a Space suggests searches as the person types, when it cleans
/// up open tabs, how it blocks content and how long it keeps what it browses.
/// A Space whose cleanup or retention changed is swept under the new rules in
/// the same edit. Its search engines have intents of their own.
public sealed record SetBrowsingPreferences(Guid WorkspaceId, Guid SpaceId, bool SearchSuggestionsEnabled,
    CurrentTabCleanup CurrentTabCleanup, ContentBlockingPolicy ContentBlocking, DataRetentionPreferences DataRetention)
    : SessionIntent(WorkspaceId);
