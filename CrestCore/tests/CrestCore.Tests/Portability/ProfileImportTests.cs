using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Finding what another browser keeps in the data folder the person chose,
/// and reading a profile's bookmarks and open tabs together into one Space
/// that keeps whatever of them could be read.
public sealed partial class BrowserContractsTests {
    /// A browser's data folder the test builds, removed with everything in it.
    private sealed class BrowserDataFolder : IDisposable {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "crest-import-" + Guid.NewGuid().ToString("N"));

        public BrowserDataFolder() => Directory.CreateDirectory(Path);

        /// Writes `contents` to `name` inside the folder, last changed at
        /// `changed` seconds since 1970, and answers its path.
        public string Write(string name, string contents = "", long changed = 1_000) {
            string file = System.IO.Path.Combine(Path, name);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file)!);
            File.WriteAllBytes(file, Encoding.UTF8.GetBytes(contents));
            File.SetLastWriteTimeUtc(file, DateTime.UnixEpoch.AddSeconds(changed));
            return file;
        }

        public void Dispose() => Directory.Delete(Path, recursive: true);
    }

    private static ImportData Found(ImportSource source, string folder) {
        using var app = Importer();
        return app.Query(new FindImportData(source, folder));
    }

    [Fact]
    public void ChromeProfilesAreFoundInOrderWithTheirNamesNewestSessionsAndPasswordStores() {
        using var chrome = new BrowserDataFolder();
        chrome.Write("Local State", """{"profile":{"info_cache":{"Profile 10":{"name":"Ten"},"Profile 2":{"name":"Two"},"Profile 3":{"name":"Gone"}}}}""");
        string personal = chrome.Write(Path.Combine("Default", "Bookmarks"), "{}");
        chrome.Write(Path.Combine("Profile 2", "Sessions", "Session_300"), changed: 100);
        string newest = chrome.Write(Path.Combine("Profile 2", "Sessions", "Tabs_200"), changed: 200);
        string store = chrome.Write(Path.Combine("Profile 2", "Login Data"));
        string ten = chrome.Write(Path.Combine("Profile 10", "Sessions", "Session_1"));
        chrome.Write(Path.Combine("System Profile", "Bookmarks"), "{}");

        var found = Found(ImportSource.Chrome, chrome.Path);

        // The first profile is first and the rest follow their numbers; a
        // profile without bookmarks or a session brings nothing.
        Assert.Equal([
            new ImportProfile("Default", "Personal", personal, null, Path.Combine(chrome.Path, "Default")),
            new ImportProfile("Profile 2", "Two", null, newest, Path.Combine(chrome.Path, "Profile 2")),
            new ImportProfile("Profile 10", "Ten", null, ten, Path.Combine(chrome.Path, "Profile 10"))
        ], found.Profiles);
        Assert.Equal([new ImportPasswordStore("Profile 2", "Two", store)], found.PasswordStores);
    }

    [Fact]
    public void ArcZenFirefoxAndSafariAreFoundWhereEachKeepsItsData() {
        using var arc = new BrowserDataFolder();
        string sidebar = arc.Write("StorableSidebar.json", "{}");
        string arcStore = arc.Write(Path.Combine("User Data", "Profile 1", "Login Data"));
        var arcData = Found(ImportSource.Arc, arc.Path);
        Assert.Equal([new ImportProfile("arc", "Arc", null, sidebar, Path.Combine(arc.Path, "User Data", "Default"))], arcData.Profiles);
        Assert.Equal([new ImportPasswordStore("Profile 1", "Profile 1", arcStore)], arcData.PasswordStores);

        using var zen = new BrowserDataFolder();
        zen.Write(Path.Combine("first", "zen-sessions.jsonlz4"), changed: 100);
        string current = zen.Write(Path.Combine("current", "zen-sessions.jsonlz4"), changed: 200);
        Assert.Equal([new ImportProfile("current", "Zen", null, current)], Found(ImportSource.Zen, zen.Path).Profiles);

        using var firefox = new BrowserDataFolder();
        firefox.Write(Path.Combine("main", "sessionstore-backups", "recovery.jsonlz4"), changed: 100);
        string latest = firefox.Write(Path.Combine("main", "sessionstore.jsonlz4"), changed: 200);
        firefox.Write(Path.Combine("empty", "times.json"));
        Assert.Equal([new ImportProfile("main", "main", null, latest)], Found(ImportSource.Firefox, firefox.Path).Profiles);

        using var safari = new BrowserDataFolder();
        string bookmarks = safari.Write("Bookmarks.plist"), session = safari.Write("LastSession.plist");
        var safariData = Found(ImportSource.Safari, safari.Path);
        Assert.Equal([new ImportProfile("safari", "Safari", bookmarks, session)], safariData.Profiles);
        Assert.Empty(safariData.PasswordStores);

        using var nothing = new BrowserDataFolder();
        Assert.Empty(Found(ImportSource.Chrome, Path.Combine(nothing.Path, "Missing")).Profiles);
    }

    [Fact]
    public void AProfileBringsItsBookmarksAndOpenTabsAsOneSpaceNamedForIt() {
        string root = ImportFixture("chrome-profile", "");
        using var app = Importer();
        var spaces = app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Personal", Path.Combine(root, "Default", "Bookmarks"), Path.Combine(root, "Default", "Sessions", "Session_1")),
            new("Profile 1", "Work", null, Path.Combine(root, "Profile 1", "Sessions", "Session_1")),
            new("Profile 2", "Locked", Path.Combine(root, "Profile 2", "Bookmarks"), Path.Combine(root, "Profile 2", "Sessions", "Session_1"))
        ])).Spaces;

        Assert.Equal(["Personal", "Work", "Locked"], spaces.Select(space => space.Settings.Name));
        Assert.All(spaces, space => Assert.Equal(("globe", SpaceAccent.Orange), (space.Settings.Symbol, space.Settings.Accent)));
        // Every bookmark root becomes a folder, the named ones after Chrome's
        // own in the order of their keys, and a browser page is dropped.
        Assert.Equal([
            ("Bookmarks bar", null), ("Other bookmarks", null), ("Reference", "Other bookmarks"), ("Untitled Folder", "Other bookmarks"),
            ("Mobile bookmarks", null), ("Alpha root", null), ("Zeta root", null)
        ], FoldersOf(spaces[0]));
        Assert.Equal([
            ("Chromium", TabPlacement.Saved, "https://www.chromium.org/", "Bookmarks bar"),
            ("untitled.example", TabPlacement.Saved, "https://untitled.example/path", "Bookmarks bar"),
            ("WebKit", TabPlacement.Saved, "https://webkit.org/", "Reference"),
            ("Alpha", TabPlacement.Saved, "https://alpha.example/", "Alpha root"),
            ("Zeta", TabPlacement.Saved, "https://zeta.example/", "Zeta root"),
            ("Open", TabPlacement.Pinned, "https://open.example/", null),
            ("Second", TabPlacement.Current, "https://second.example/", null)
        ], TabsOf(spaces[0]));
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_725_526_400), spaces[0].Tabs[0].LastActivatedAt);
        Assert.Equal(["Open", "Second"], spaces[1].Tabs.Select(tab => tab.Title));
        // A profile-encrypted session leaves the profile its bookmarks.
        Assert.DoesNotContain(spaces[2].Tabs, tab => tab.Placement != TabPlacement.Saved);
        Assert.Equal(5, spaces[2].Tabs.Count);
    }

    [Fact]
    public void SafariBookmarksKeepTheirFoldersAndEachDateUnitSafariWrote() {
        string root = ImportFixture("safari-profile", "");
        using var app = Importer();
        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Safari, [
            new("safari", "Safari", Path.Combine(root, "Bookmarks.plist"), Path.Combine(root, "LastSession.plist"))
        ])).Spaces);

        Assert.Equal([("Favorites", null), ("Empty", null)], FoldersOf(space));
        Assert.Equal([
            ("Safari", TabPlacement.Saved, "https://developer.apple.com/safari/", "Favorites"),
            ("seconds.example", TabPlacement.Saved, "https://seconds.example/", "Favorites"),
            ("micro.example", TabPlacement.Saved, "https://micro.example/", "Favorites"),
            ("Top", TabPlacement.Saved, "https://top.example/", null),
            ("Open", TabPlacement.Current, "https://open.safari.example/", null)
        ], TabsOf(space));
        Assert.All(space.Tabs.Take(3), tab => Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_600_000_000), tab.LastActivatedAt));
    }

    [Fact]
    public void AProfileKeepsWhateverCouldBeReadAndIsRefusedOnlyWhenNothingCould() {
        using var app = Importer();
        string safari = ImportFixture("safari-bad-bookmarks", "");
        var openTabs = Assert.Single(app.Query(new ReadImport(ImportSource.Safari, [
            new("safari", "Safari", Path.Combine(safari, "Bookmarks.plist"), Path.Combine(safari, "LastSession.plist"))
        ])).Spaces);
        Assert.Equal([("Open", TabPlacement.Current, "https://open.safari.example/", null)], TabsOf(openTabs));

        // Nothing read: the refusal is the last thing that went wrong.
        string broken = ImportFixture("chrome-broken-both", "Default");
        Assert.IsType<SessionEncrypted>(Assert.Throws<Rejected>(() => app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Personal", Path.Combine(broken, "Bookmarks"), Path.Combine(broken, "Sessions", "Session_1"))
        ]))).Rejection);
        // Bookmarks nested deeper than a folder can be are refused before
        // any Space is made.
        Assert.IsType<BookmarksOverLimits>(Assert.Throws<Rejected>(() => app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Personal", ImportFixture("chrome-deep", Path.Combine("Default", "Bookmarks")), null)
        ]))).Rejection);
    }
}
