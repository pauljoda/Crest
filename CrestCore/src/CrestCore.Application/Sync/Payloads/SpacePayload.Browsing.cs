using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed partial record SpacePayload {
    #region Static Variables

    /// The most custom engines a client asks the core to restore at once;
    /// past it, a client keeps its engines as they are.
    private const int MaximumRestoredProviders = SearchPreferences.MaximumCustomProviders * 2;

    #endregion

    #region Actions - Browsing preferences

    /// Browsing preferences as every client reads them. The tab cleanup is
    /// required and every closed choice must be one clients know; the engines
    /// are all or none; the selection falls back to the legacy member, then to
    /// Google; and engines that no longer validate are left out, with a
    /// selection that named one falling back to Google.
    private static BrowsingPreferences ReadBrowsingPreferences(SyncPayloadReader value) {
        string legacy = value.OptionalText(StoredSessionCodec.Key.LegacySearchProvider) ?? BuiltInSearchEngine.Google.Name;
        string selected = value.TolerantText(StoredSessionCodec.Key.SelectedSearchProviderId) ?? legacy;
        var providers = CustomProviders(value.Value[StoredSessionCodec.Key.CustomSearchProviders]);
        bool suggestions = value.TolerantFlag(StoredSessionCodec.Key.SearchSuggestionsEnabled) ?? false;
        var cleanup = value.Named(StoredSessionCodec.Key.CurrentTabCleanupPolicy, CurrentTabCleanup.Named);
        var blocking = value.OptionalNamed(StoredSessionCodec.Key.ContentBlockingPolicy, ContentBlockingPolicy.Named) ?? ContentBlockingPolicy.Balanced;
        var retention = value.OptionalNested(StoredSessionCodec.Key.DataRetention) is { } kept
            ? new DataRetentionPreferences(kept.Named(StoredSessionCodec.Key.History, DataRetention.Named),
                kept.Named(StoredSessionCodec.Key.Archive, DataRetention.Named), kept.Named(StoredSessionCodec.Key.Downloads, DataRetention.Named))
            : StoredSessionCodec.DefaultBrowsingPreferences.DataRetention;
        (providers, selected) = Restored(providers, selected);
        var (builtIn, custom) = StoredSessionCodec.SearchSelection(selected);
        return new(builtIn, custom, providers, suggestions, cleanup, blocking, retention);
    }

    /// The custom engines a record holds, or none when any of them is not an
    /// engine every client reads.
    private static IReadOnlyList<CustomSearchProvider> CustomProviders(JsonNode? node) {
        if (node is null) return [];
        try {
            return [.. (node as JsonArray ?? throw new UnreadableSyncPayloadException()).Select(item => {
                var provider = new SyncPayloadReader(item, SyncPayloadForm.Journal);
                return new CustomSearchProvider(provider.Identity(StoredSessionCodec.Key.Id), provider.Text(StoredSessionCodec.Key.Name),
                    provider.Text(StoredSessionCodec.Key.SearchUrlTemplate), provider.OptionalText(StoredSessionCodec.Key.SuggestionUrlTemplate));
            })];
        } catch (UnreadableSyncPayloadException) {
            return [];
        }
    }

    /// The engines a Space keeps of `providers`, those that still validate
    /// once each, and the engine `selected` names among them or the built-ins,
    /// else Google.
    private static (IReadOnlyList<CustomSearchProvider> Providers, string Selected) Restored(
        IReadOnlyList<CustomSearchProvider> providers, string selected) {
        if (providers.Count is > 0 and <= MaximumRestoredProviders) {
            var admitted = new List<(CustomSearchProvider Stored, SearchProvider Admitted)>();
            foreach (var stored in providers) {
                try {
                    admitted.Add((stored, SearchProvider.Admit(stored.Id, stored.Name, stored.SearchUrlTemplate, stored.SuggestionUrlTemplate)));
                } catch (Rejected) {
                    // Left out; see the summary.
                }
            }
            var restored = SearchPreferences.Restore(selected, admitted.Select(entry => entry.Admitted), false);
            return ([.. restored.CustomProviders.Select(provider => admitted.First(entry => ReferenceEquals(entry.Admitted, provider)).Stored)],
                restored.SelectedId);
        }
        var available = SearchProvider.All.Select(provider => provider.Name).Concat(providers.Select(provider => SearchProvider.CustomId(provider.Id)));
        return (providers, available.Contains(selected, StringComparer.Ordinal) ? selected : BuiltInSearchEngine.Google.Name);
    }

    #endregion
}
