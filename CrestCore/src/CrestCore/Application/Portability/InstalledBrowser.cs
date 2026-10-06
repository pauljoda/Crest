using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// How Crest reads each browser it imports from: where in its data folder it
/// keeps each profile's bookmarks, latest session and saved passwords, and
/// the readers for those files. A browser's `Source` is what the platform and
/// the person see of it.
internal sealed class InstalledBrowser {
    #region Static Variables

    public static readonly InstalledBrowser Arc = new(ImportSource.Arc, ArcProfiles, folder => ChromiumPasswordStores(folder.Child("User Data")),
        ArcSidebar.Read, bookmarks: null, extensions: true);
    public static readonly InstalledBrowser Zen = new(ImportSource.Zen, ZenProfiles, _ => [], ZenSessions.Read, bookmarks: null);
    public static readonly InstalledBrowser Chrome = new(ImportSource.Chrome, ChromiumProfiles, ChromiumPasswordStores,
        (contents, importedAt) => ChromiumSession.Read(contents, importedAt), ChromeBookmarks.Read, extensions: true);
    public static readonly InstalledBrowser Safari = new(ImportSource.Safari, SafariProfiles, _ => [], SafariSession.Read,
        SafariBookmarks.Read);
    public static readonly InstalledBrowser Firefox = new(ImportSource.Firefox, FirefoxProfiles, _ => [], FirefoxSession.Read,
        bookmarks: null);

    public static IReadOnlyList<InstalledBrowser> All { get; } = [Arc, Zen, Chrome, Safari, Firefox];

    /// The largest session file an import reads.
    public const long MaximumSessionBytes = 512L * 1024 * 1024;
    /// The largest bookmark file an import reads.
    public const long MaximumBookmarkBytes = 50L * 1024 * 1024;

    private const string ChromiumDefaultProfile = "Default";
    private const string ChromiumProfilePrefix = "Profile ";
    /// What Chrome's first profile is called when the person never named it.
    private const string ChromiumDefaultName = "Personal";

    private static readonly string[] ChromiumSessionNames = ["Current Session", "Current Tabs"];
    private static readonly string[] ChromiumSessionPrefixes = ["Session_", "Tabs_"];
    private static readonly string[] FirefoxSessionNames = ["recovery.jsonlz4", "sessionstore.jsonlz4"];

    #endregion

    #region Types

    private delegate IReadOnlyList<SessionDraft> SessionReader(byte[] contents, DateTimeOffset importedAt);

    private delegate BookmarkDraft BookmarkReader(byte[] contents, DateTimeOffset importedAt);

    #endregion

    #region Variables

    public ImportSource Source { get; }

    private readonly Func<ImportFolder, IReadOnlyList<ImportProfile>> profiles;
    private readonly Func<ImportFolder, IReadOnlyList<ImportPasswordStore>> passwordStores;
    private readonly SessionReader sessions;
    private readonly BookmarkReader? bookmarks;
    private readonly bool offersExtensions;

    #endregion

    #region Constructors

    private InstalledBrowser(ImportSource source, Func<ImportFolder, IReadOnlyList<ImportProfile>> profiles,
        Func<ImportFolder, IReadOnlyList<ImportPasswordStore>> passwordStores, SessionReader sessions, BookmarkReader? bookmarks,
        bool extensions = false) {
        Source = source;
        offersExtensions = extensions;
        this.profiles = profiles;
        this.passwordStores = passwordStores;
        this.sessions = sessions;
        this.bookmarks = bookmarks;
    }

    #endregion

    #region Actions - Lookup

    public static InstalledBrowser Of(ImportSource source) => All.First(browser => browser.Source == source);

    #endregion

    #region Actions - Finding

    /// What the browser keeps in `folder`.
    public ImportData Find(string folder) {
        var data = new ImportFolder(folder);
        return new(profiles(data), passwordStores(data));
    }

    private static IReadOnlyList<ImportProfile> ArcProfiles(ImportFolder folder) =>
        folder.File("StorableSidebar.json") is { } sidebar
            ? [new ImportProfile("arc", ImportSource.Arc.Title, null, sidebar, folder.Child("User Data").Child(ChromiumDefaultProfile).Path)] : [];

    private static IReadOnlyList<ImportProfile> ZenProfiles(ImportFolder folder) =>
        folder.Newest(["zen-sessions.jsonlz4"]) is { } session
            ? [new ImportProfile(new ImportFolder(Path.GetDirectoryName(session)!).Name, ImportSource.Zen.Title, null, session)] : [];

    private static IReadOnlyList<ImportProfile> SafariProfiles(ImportFolder folder) {
        string? bookmarks = folder.File("Bookmarks.plist"), session = folder.File("LastSession.plist");
        return bookmarks is null && session is null ? [] : [new ImportProfile("safari", ImportSource.Safari.Title, bookmarks, session)];
    }

    private static IReadOnlyList<ImportProfile> FirefoxProfiles(ImportFolder folder) =>
        [.. folder.Folders().Select(profile => profile.Newest(FirefoxSessionNames) is { } session
            ? new ImportProfile(profile.Name, profile.Name, null, session) : null).OfType<ImportProfile>()];

    /// Chrome's profiles: those its `Local State` names and the profile
    /// folders it keeps, the first profile first, each named as the person
    /// named it.
    private static IReadOnlyList<ImportProfile> ChromiumProfiles(ImportFolder folder) {
        var names = ChromiumProfileNames(folder);
        var directories = names.Keys.Union(folder.Folders().Select(profile => profile.Name).Where(IsChromiumProfile), StringComparer.Ordinal);
        return [.. directories.Order(ChromiumProfileOrder.Instance).Select(directory => {
            var profile = folder.Child(directory);
            string? bookmarks = profile.File("Bookmarks");
            string? session = profile.Child("Sessions").Newest(ChromiumSessionNames, ChromiumSessionPrefixes);
            return bookmarks is null && session is null ? null
                : new ImportProfile(directory, ChromiumProfileName(names, directory), bookmarks, session, profile.Path);
        }).OfType<ImportProfile>()];
    }

    /// The saved-password stores of the Chromium profiles below `root`.
    private static IReadOnlyList<ImportPasswordStore> ChromiumPasswordStores(ImportFolder root) {
        var names = ChromiumProfileNames(root);
        return [.. root.Folders().Where(profile => IsChromiumProfile(profile.Name)).OrderBy(profile => profile.Name, ChromiumProfileOrder.Instance)
            .Select(profile => profile.File("Login Data") is { } store
                ? new ImportPasswordStore(profile.Name, ChromiumProfileName(names, profile.Name), store) : null)
            .OfType<ImportPasswordStore>()];
    }

    private static bool IsChromiumProfile(string name) =>
        name == ChromiumDefaultProfile || name.StartsWith(ChromiumProfilePrefix, StringComparison.Ordinal);

    private static string ChromiumProfileName(IReadOnlyDictionary<string, string> names, string directory) =>
        names.TryGetValue(directory, out var name) ? name : directory == ChromiumDefaultProfile ? ChromiumDefaultName : directory;

    /// The name the person gave each profile, from `Local State`.
    private static Dictionary<string, string> ChromiumProfileNames(ImportFolder root) {
        using var state = root.Json("Local State");
        Dictionary<string, string> names = new(StringComparer.Ordinal);
        if (state is null) return names;
        var cache = ImportJson.Member(ImportJson.Member(state.RootElement, "profile"), "info_cache");
        foreach (var entry in ImportJson.Members(cache))
            if (ImportJson.Text(ImportJson.Member(entry.Value, "name")) is { } name && name.Trim().Length > 0) names[entry.Name] = name;
        return names;
    }

    #endregion

    #region Actions - Reading

    /// The Spaces `profiles` bring. See `ReadImport`.
    public ImportedSpaces Read(IReadOnlyList<ImportProfile> profiles, ImportSpaceNames names, IIdSource ids,
        DateTimeOffset now) {
        List<SpaceState> spaces = [];
        List<ImportSpaceExtensions> extensions = [];
        Rejection? lastFailure = null;
        foreach (var profile in profiles) {
            if (Source.NamesItsSpaces) {
                if (profile.SessionPath is not { } path) continue;
                var named = SessionDraft.Spaces(Sessions(path, now), Source, names, ids, now);
                spaces.AddRange(named);
                // The sidebar's Spaces share the browser's profile, so each offers what it has installed.
                AddExtensions(extensions, profile, named);
                continue;
            }
            SpaceState? combined = null;
            if (profile.BookmarksPath is { } bookmarkPath && bookmarks is not null) {
                try {
                    combined = Bookmarks(bookmarkPath, now).Space(Source, ids, now);
                } catch (Rejected rejected) {
                    lastFailure = rejected.Rejection;
                }
            }
            if (profile.SessionPath is { } sessionPath) {
                try {
                    combined = Merged(SessionDraft.Spaces(Sessions(sessionPath, now), Source, names, ids, now), combined);
                } catch (Rejected rejected) {
                    lastFailure = rejected.Rejection;
                }
            }
            if (combined is null) continue;
            var space = combined with { Settings = combined.Settings with { Name = profile.Name, Symbol = Source.Symbol, Accent = Source.Accent } };
            spaces.Add(space);
            AddExtensions(extensions, profile, [space]);
        }
        if (spaces.Count == 0) throw new Rejected(lastFailure ?? new SessionHasNoTabs());
        return spaces.Count > BrowserDataFile.MaximumSpaces ? throw new Rejected(new SessionOverLimits()) : new(spaces, extensions);
    }

    /// Offers `spaces` the Web Store extensions `profile` has installed, when
    /// the browser keeps them where Crest reads them and the profile has any.
    private void AddExtensions(List<ImportSpaceExtensions> offers, ImportProfile profile, IEnumerable<SpaceState> spaces) {
        if (!offersExtensions || profile.ProfilePath is not { } path) return;
        var installed = ChromiumExtensions.Read(new ImportFolder(path));
        if (installed.Count == 0) return;
        offers.AddRange(spaces.Select(space => new ImportSpaceExtensions(space.Id, installed)));
    }

    private IReadOnlyList<SessionDraft> Sessions(string path, DateTimeOffset now) {
        var contents = ImportFile.Read(path, MaximumSessionBytes, new SessionTooLarge(), new SessionUnrecognized());
        try {
            return sessions(contents, now);
        } catch (Exception error) when (error is not Rejected) {
            throw new Rejected(new SessionUnrecognized());
        }
    }

    private BookmarkDraft Bookmarks(string path, DateTimeOffset now) {
        var contents = ImportFile.Read(path, MaximumBookmarkBytes, new BookmarksTooLarge(), new FileUnreadable());
        try {
            return bookmarks!(contents, now);
        } catch (Exception error) when (error is not Rejected) {
            throw new Rejected(new BookmarksUnrecognized());
        }
    }

    /// One profile's Space: its bookmarks' Space, or its first window's,
    /// joined by each of its windows that fits, in order.
    private SpaceState? Merged(IReadOnlyList<SpaceState> windows, SpaceState? bookmarks) {
        if ((bookmarks ?? windows.FirstOrDefault()) is not { } result) return null;
        foreach (var window in bookmarks is null ? windows.Skip(1) : windows) {
            if (result.Tabs.Count + window.Tabs.Count > SessionDraft.MaximumTabs
                || result.Folders.Count + window.Folders.Count > FolderTree.MaximumCount) continue;
            result = result with { Folders = [.. result.Folders, .. window.Folders], Tabs = [.. result.Tabs, .. window.Tabs] };
        }
        return result;
    }

    #endregion
}
