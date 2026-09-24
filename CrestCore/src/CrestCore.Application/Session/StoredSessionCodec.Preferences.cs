using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    private static readonly StoredSpellings<StartupBehavior> StartupBehaviors = new([
        (StartupBehavior.ShowStartPage, "showStartPage"), (StartupBehavior.LastActiveTab, "lastActiveTab")
    ]);
    private static readonly StoredSpellings<SavedTabClosePolicy> SavedTabClosePolicies = new([
        (SavedTabClosePolicy.ResumeLastLocation, "resumeLastLocation"), (SavedTabClosePolicy.ReturnToSavedUrl, "returnToSavedURL")
    ]);

    /// What a Space that stored no browsing preferences searches and keeps.
    internal static BrowsingPreferences DefaultBrowsingPreferences { get; } = new(SearchProvider.Google.Name, [], false,
        CurrentTabCleanup.After12Hours, ContentBlockingPolicy.Balanced,
        new(DataRetention.Forever, DataRetention.Forever, DataRetention.Forever));

    /// What a Space that stored no credential preferences offers.
    internal static CredentialPreferences DefaultCredentialPreferences { get; } = new(true, true, false);

    #endregion

    #region Actions - Browsing preferences

    /// A Space's browsing preferences. The selection falls back to the legacy
    /// provider member, a custom engine without a readable identity is left out,
    /// a missing cleanup policy is twelve hours and an unknown one never cleans.
    internal static BrowsingPreferences DecodeBrowsingPreferences(JsonNode? node) {
        var value = Object(node);
        var retention = value[Key.DataRetention] as JsonObject;
        DataRetention Kept(string key) => DataRetention.Named(TolerantText(retention?[key])) ?? DataRetention.Forever;
        var cleanup = value[Key.CurrentTabCleanupPolicy] is { } stored
            ? CurrentTabCleanup.Named(TolerantText(stored)) ?? CurrentTabCleanup.Never : CurrentTabCleanup.After12Hours;
        return new(TolerantText(value[Key.SelectedSearchProviderId]) ?? TolerantText(value[Key.LegacySearchProvider])
                ?? SearchProvider.Google.Name,
            Items(value[Key.CustomSearchProviders]).OfType<JsonObject>().Select(CustomSearchProvider).OfType<CustomSearchProvider>().ToArray(),
            TolerantFlag(value[Key.SearchSuggestionsEnabled]) ?? false, cleanup,
            ContentBlockingPolicy.Named(TolerantText(value[Key.ContentBlockingPolicy])) ?? ContentBlockingPolicy.Balanced,
            new(Kept(Key.History), Kept(Key.Archive), Kept(Key.Downloads)));
    }

    /// Older builds read only the legacy provider member, so a custom selection
    /// keeps Google there as their safe fallback.
    internal static JsonObject Encode(BrowsingPreferences preferences) => new() {
        [Key.LegacySearchProvider] = preferences.SelectedSearchProviderId.StartsWith(SearchProvider.CustomPrefix, StringComparison.Ordinal)
            ? SearchProvider.Google.Name : preferences.SelectedSearchProviderId,
        [Key.SelectedSearchProviderId] = preferences.SelectedSearchProviderId,
        [Key.CustomSearchProviders] = new JsonArray(preferences.CustomSearchProviders.Select(provider => {
            var value = new JsonObject {
                [Key.Id] = BareIdentity(provider.Id),
                [Key.Name] = provider.Name,
                [Key.SearchUrlTemplate] = provider.SearchUrlTemplate
            };
            Put(value, Key.SuggestionUrlTemplate, provider.SuggestionUrlTemplate);
            return (JsonNode?)value;
        }).ToArray()),
        [Key.SearchSuggestionsEnabled] = preferences.SearchSuggestionsEnabled,
        [Key.CurrentTabCleanupPolicy] = preferences.CurrentTabCleanup.Name,
        [Key.ContentBlockingPolicy] = preferences.ContentBlocking.Name,
        [Key.DataRetention] = new JsonObject {
            [Key.History] = preferences.DataRetention.History.Name,
            [Key.Archive] = preferences.DataRetention.Archive.Name,
            [Key.Downloads] = preferences.DataRetention.Downloads.Name
        }
    };

    private static CustomSearchProvider? CustomSearchProvider(JsonObject value) =>
        Guid.TryParse(TolerantText(value[Key.Id]), out var id)
            ? new(id, TolerantText(value[Key.Name]) ?? "", TolerantText(value[Key.SearchUrlTemplate]) ?? "",
                TolerantText(value[Key.SuggestionUrlTemplate]))
            : null;

    #endregion

    #region Actions - Credential preferences

    internal static CredentialPreferences DecodeCredentialPreferences(JsonNode? node) {
        var value = Object(node);
        return new(Flag(value[Key.IsEnabled]) ?? DefaultCredentialPreferences.IsEnabled,
            Flag(value[Key.SyncsCrestPasswordsWithICloud]) ?? DefaultCredentialPreferences.SyncsCrestPasswordsWithICloud,
            Flag(value[Key.AlsoOffersSaveToSystemPasswords]) ?? DefaultCredentialPreferences.AlsoOffersSaveToSystemPasswords);
    }

    internal static JsonObject Encode(CredentialPreferences preferences) => new() {
        [Key.IsEnabled] = preferences.IsEnabled,
        [Key.SyncsCrestPasswordsWithICloud] = preferences.SyncsCrestPasswordsWithICloud,
        [Key.AlsoOffersSaveToSystemPasswords] = preferences.AlsoOffersSaveToSystemPasswords
    };

    #endregion

    #region Actions - App preferences

    /// The app-wide preferences. A value this build cannot read keeps its default,
    /// and translation rules that no longer validate read as none, which never
    /// translates.
    internal static AppPreferences DecodeAppPreferences(JsonNode? node) {
        var value = Object(node);
        var defaults = AppPreferencesPolicy.Default;
        return new(StartupBehaviors.Parse(TolerantText(value[Key.StartupBehavior])) ?? defaults.Startup,
            TolerantFlag(value[Key.OffersTranslation]) ?? defaults.OffersTranslation,
            TolerantFlag(value[Key.AutomaticallyTranslates]) ?? defaults.AutomaticallyTranslates,
            TranslationRules(value[Key.TranslationRules]),
            TolerantFlag(value[Key.ChecksSpelling]) ?? defaults.ChecksSpelling,
            TolerantFlag(value[Key.AutomaticallyEntersPictureInPicture]) ?? defaults.AutomaticallyEntersPictureInPicture,
            SavedTabClosePolicies.Parse(TolerantText(value[Key.SavedTabClosePolicy])) ?? defaults.SavedTabClose,
            TolerantFlag(value[Key.SavedTabFaviconReturnsToSavedUrl]) ?? defaults.SavedTabFaviconReturnsToSavedUrl,
            TolerantFlag(value[Key.SplitFocusFollowsMouse]) ?? defaults.SplitFocusFollowsMouse);
    }

    internal static JsonObject Encode(AppPreferences preferences) => new() {
        [Key.StartupBehavior] = StartupBehaviors.Name(preferences.Startup),
        [Key.OffersTranslation] = preferences.OffersTranslation,
        [Key.AutomaticallyTranslates] = preferences.AutomaticallyTranslates,
        [Key.TranslationRules] = EncodeTranslationRules(preferences.TranslationRules),
        [Key.ChecksSpelling] = preferences.ChecksSpelling,
        [Key.AutomaticallyEntersPictureInPicture] = preferences.AutomaticallyEntersPictureInPicture,
        [Key.SavedTabClosePolicy] = SavedTabClosePolicies.Name(preferences.SavedTabClose),
        [Key.SavedTabFaviconReturnsToSavedUrl] = preferences.SavedTabFaviconReturnsToSavedUrl,
        [Key.SplitFocusFollowsMouse] = preferences.SplitFocusFollowsMouse
    };

    /// The values the native settings stored before the core owned them, each
    /// under its stored name and null when never saved. Translation rules arrive
    /// as the raw JSON text the native setting stored. A value this build cannot
    /// read keeps its default rather than failing the whole import.
    internal static AppPreferences ImportAppPreferences(JsonObject legacy) {
        var stored = legacy.DeepClone().AsObject();
        stored[Key.TranslationRules] = RawTranslationRules(legacy[Key.TranslationRules]);
        return DecodeAppPreferences(stored);
    }

    private static JsonNode? RawTranslationRules(JsonNode? value) {
        if (TolerantText(value) is not { } text) return null;
        try {
            return JsonNode.Parse(text, documentOptions: new() { MaxDepth = 8 });
        } catch (JsonException) {
            return null;
        }
    }

    /// Rules in their stored shape, `{"sources":{"es":{"targetID":"en","isEnabled":true}}}`.
    internal static IReadOnlyDictionary<string, TranslationRule> TranslationRules(JsonNode? value) {
        if (value?[Key.Sources] is not JsonObject sources) return AutomaticTranslationRules.Empty.Sources;
        try {
            return AutomaticTranslationRules.Restore(sources.Select(member => KeyValuePair.Create(member.Key,
                new TranslationRule(TolerantText(member.Value?[Key.TargetId]) ?? "", TolerantFlag(member.Value?[Key.IsEnabled]) ?? false))))
                .Sources;
        } catch (BrowserRuleException) {
            return AutomaticTranslationRules.Empty.Sources;
        }
    }

    private static JsonObject EncodeTranslationRules(IReadOnlyDictionary<string, TranslationRule> rules) {
        var sources = new JsonObject();
        foreach (var (source, rule) in rules)
            sources[source] = new JsonObject { [Key.TargetId] = rule.TargetId, [Key.IsEnabled] = rule.IsEnabled };
        return new() { [Key.Sources] = sources };
    }

    /// A startup or saved-tab close choice in its stored spelling, which settings
    /// commands and the launch plan also use; null when this build cannot name it.
    internal static StartupBehavior? ParseStartupBehavior(JsonNode? node) => StartupBehaviors.Parse(TolerantText(node));

    internal static string Spelling(StartupBehavior behavior) => StartupBehaviors.Name(behavior);

    internal static SavedTabClosePolicy? ParseSavedTabClosePolicy(JsonNode? node) => SavedTabClosePolicies.Parse(TolerantText(node));

    #endregion
}
