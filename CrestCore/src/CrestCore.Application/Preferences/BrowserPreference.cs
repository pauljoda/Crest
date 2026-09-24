using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One behavior preference a `preferences.set` command names. A preference's
/// name is its member in the stored preferences record, so a name never
/// changes. Each preference reads its value in the stored spelling and records
/// it; a value it cannot read is refused. Translation rules are edited per
/// source language rather than replaced whole.
internal sealed class BrowserPreference {
    #region Variables

    public static readonly BrowserPreference Startup = new(StoredSessionCodec.Key.StartupBehavior, (preferences, value) =>
        preferences with { Startup = StoredSessionCodec.ParseStartupBehavior(value) ?? throw Invalid() });
    public static readonly BrowserPreference OffersTranslation = Flag(StoredSessionCodec.Key.OffersTranslation,
        (preferences, value) => preferences with { OffersTranslation = value });
    public static readonly BrowserPreference AutomaticallyTranslates = Flag(StoredSessionCodec.Key.AutomaticallyTranslates,
        (preferences, value) => preferences with { AutomaticallyTranslates = value });
    public static readonly BrowserPreference ChecksSpelling = Flag(StoredSessionCodec.Key.ChecksSpelling,
        (preferences, value) => preferences with { ChecksSpelling = value });
    public static readonly BrowserPreference AutomaticallyEntersPictureInPicture = Flag(
        StoredSessionCodec.Key.AutomaticallyEntersPictureInPicture,
        (preferences, value) => preferences with { AutomaticallyEntersPictureInPicture = value });
    public static readonly BrowserPreference SavedTabClose = new(StoredSessionCodec.Key.SavedTabClosePolicy, (preferences, value) =>
        preferences with { SavedTabClose = StoredSessionCodec.ParseSavedTabClosePolicy(value) ?? throw Invalid() });
    public static readonly BrowserPreference SavedTabFaviconReturnsToSavedUrl = Flag(StoredSessionCodec.Key.SavedTabFaviconReturnsToSavedUrl,
        (preferences, value) => preferences with { SavedTabFaviconReturnsToSavedUrl = value });
    public static readonly BrowserPreference SplitFocusFollowsMouse = Flag(StoredSessionCodec.Key.SplitFocusFollowsMouse,
        (preferences, value) => preferences with { SplitFocusFollowsMouse = value });

    public static IReadOnlyList<BrowserPreference> All { get; } = [Startup, OffersTranslation, AutomaticallyTranslates, ChecksSpelling,
        AutomaticallyEntersPictureInPicture, SavedTabClose, SavedTabFaviconReturnsToSavedUrl, SplitFocusFollowsMouse];

    private readonly Func<AppPreferences, JsonNode?, AppPreferences> apply;

    public string Name { get; }

    #endregion

    #region Constructors

    private BrowserPreference(string name, Func<AppPreferences, JsonNode?, AppPreferences> apply) {
        Name = name;
        this.apply = apply;
    }

    /// A preference whose value is a JSON boolean.
    private static BrowserPreference Flag(string name, Func<AppPreferences, bool, AppPreferences> record) =>
        new(name, (preferences, value) => record(preferences, PreferenceCodes.Flag(value) ?? throw Invalid()));

    #endregion

    #region Actions - Lookup

    public static BrowserPreference? Named(string? name) => All.FirstOrDefault(preference => preference.Name == name);

    #endregion

    #region Actions - Preferences

    /// The preferences with this preference set to `value`, in its stored spelling.
    public AppPreferences Apply(AppPreferences preferences, JsonNode? value) {
        ArgumentNullException.ThrowIfNull(preferences);
        return apply(preferences, value);
    }

    private static BrowserRuleException Invalid() => new(BrowserRuleCodes.InvalidPreferenceValue);

    #endregion
}
