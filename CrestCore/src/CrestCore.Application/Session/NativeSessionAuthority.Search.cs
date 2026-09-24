using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Search engines

    /// `space` with its search choice edited by `edit`, through the rules a
    /// Space's engines follow. Stored engines that no longer validate are left
    /// out, as reading them does.
    private SessionEdit Searching(SessionState basis, SpaceState space, Func<SearchPreferences, SearchPreferences> edit) =>
        SettingSpace(basis, space, settings => settings with {
            BrowsingPreferences = edit(SearchPreferences.Restore(settings.BrowsingPreferences)).Applied(settings.BrowsingPreferences)
        }, SyncStaging.Edit);

    private SessionEdit AddingSearchEngine(SessionState basis, AddSearchEngine intent) {
        RequireOwnedSpaces();
        var engine = Admitted(intent.Engine);
        return Searching(basis, Editable(basis, intent.SpaceId), search => {
            var added = search.Add(engine);
            return intent.Selects ? added.Select(engine) : added;
        });
    }

    private SessionEdit UpdatingSearchEngine(SessionState basis, UpdateSearchEngine intent) {
        RequireOwnedSpaces();
        var engine = Admitted(intent.Engine);
        return Searching(basis, Editable(basis, intent.SpaceId), search => search.Update(engine));
    }

    private SessionEdit RemovingSearchEngine(SessionState basis, RemoveSearchEngine intent) {
        RequireOwnedSpaces();
        return Searching(basis, Editable(basis, intent.SpaceId), search => search.Remove(intent.EngineId));
    }

    private SessionEdit SelectingSearchEngine(SessionState basis, SelectSearchEngine intent) {
        RequireOwnedSpaces();
        var space = Editable(basis, intent.SpaceId);
        return Searching(basis, space, search => (intent.BuiltIn, intent.CustomEngineId) switch {
            ( { } builtIn, null) => search.Select(builtIn.Provider()),
            (null, { } custom) => search.Select(custom),
            _ => throw new Rejected(new UnknownSearchEngine(intent.CustomEngineId))
        });
    }

    /// A custom engine as the person typed it, trimmed and validated. Throws
    /// `Rejected` with `InvalidSearchEngine` naming its first flaw.
    private static SearchProvider Admitted(CustomSearchEngine engine) =>
        SearchProvider.Admit(engine.Id, engine.Name, engine.SearchTemplate, engine.SuggestionTemplate);

    #endregion

    #region Actions - Browsing preferences

    /// Sets the Space's browsing preferences apart from its search engines. A
    /// changed cleanup or retention sweeps the Space under the new rules in
    /// the same edit, which then stages as the records it expired.
    private SessionEdit SettingBrowsingPreferences(SessionState basis, SetBrowsingPreferences intent, DateTimeOffset now) {
        RequireOwnedSpaces();
        var space = Editable(basis, intent.SpaceId);
        var before = space.Settings.BrowsingPreferences;
        var preferences = before with {
            SearchSuggestionsEnabled = intent.SearchSuggestionsEnabled,
            CurrentTabCleanup = intent.CurrentTabCleanup,
            ContentBlocking = intent.ContentBlocking,
            DataRetention = intent.DataRetention
        };
        var configured = Configured(space, space.Settings with { BrowsingPreferences = preferences });
        if (before.CurrentTabCleanup == preferences.CurrentTabCleanup && before.DataRetention == preferences.DataRetention)
            return new(Replacing(basis, configured), SyncStaging.Edit);
        var swept = Expired(CleanedUp(configured, now, device?.ShownTabs(workspaceId)), now);
        return new(Replacing(basis, swept), SameRecords(configured, swept) ? SyncStaging.Edit : SyncStaging.Expiry);
    }

    /// Whether two states of one Space hold the same tabs, history and archive.
    private static bool SameRecords(SpaceState before, SpaceState after) =>
        before.Tabs.SequenceEqual(after.Tabs) && before.History.SequenceEqual(after.History)
        && before.ArchivedTabs.SequenceEqual(after.ArchivedTabs);

    #endregion
}
