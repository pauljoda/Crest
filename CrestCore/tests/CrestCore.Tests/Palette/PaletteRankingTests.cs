using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// How the palette decides what leads and in what order: inline completion
/// follows other browsers and Return opens what the field shows, text that
/// names no address searches first unless it is one word that names a tab or
/// a site the person uses, a typed fragment survives, a place shows
/// once as its strongest kind, picks for the same text lead and can be
/// forgotten, a private window remembers nothing, site searches answer only
/// to their exact shortcut and search only their site, and what the palette
/// remembers survives the device store.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void APrivateWindowRemembersNothing() {
        var (session, space) = PaletteSession([], ("https://news.example.org/today", "Today", 1, 2, 1));
        using var device = new TestDevice(session, WorkspaceKind.Named("private"));
        var window = device.Open(space);
        var history = device.Query(Asking(window, "news")).Groups.SelectMany(group => group.Rows).First(row => row.Kind == PaletteRowKind.History);

        device.Send(new RecordPaletteChoice(window, "news", history));
        device.Send(new RecordPaletteChoice(window, "news", history));

        var answer = device.Query(Asking(window, "news"));
        Assert.Null(answer.Completion);
        Assert.DoesNotContain(answer.Groups.SelectMany(group => group.Rows), row => row.Reason == PaletteReason.Learned);
    }

    /// The address row for a site typed without a scheme falls back to http
    /// only when the Space doesn't know the site: one it knows opens the way
    /// it knows it, and an address typed with https:// never falls back.
    [Fact]
    public void OnlyAnUnknownSiteTypedWithoutASchemeOffersAnHttpFallback() {
        var (session, space) = PaletteSession([], ("https://example.org/", "Example", 3, 2, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);
        PaletteRow Address(string text) =>
            device.Query(Asking(window, text)).Groups.SelectMany(group => group.Rows).First(row => row.Kind == PaletteRowKind.OpenAddress);

        Assert.Equal(("https://example.org/", (string?)null), (Address("example.org").Address, Address("example.org").HttpFallback));
        Assert.Equal(("https://httpforever.com", "http://httpforever.com"),
            (Address("httpforever.com").Address, Address("httpforever.com").HttpFallback));
        Assert.Null(Address("https://httpforever.com").HttpFallback);
    }

    /// A typed address the Space knows under another spelling opens that
    /// spelling with the fragment the person typed, or none, never the
    /// fragment the Space's tab or history holds, and the field never
    /// completes one they didn't type.
    [Fact]
    public void AKnownAddressOpensWithTheFragmentThePersonTyped() {
        var (session, space) = PaletteSession([OpenTab(Guid.NewGuid(), "Views", "https://app.example/#view=001")],
            ("https://www.example.org/wiki/Page", "Page", 3, 2, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);
        string? Opens(string text) =>
            device.Query(Asking(window, text)).Groups.SelectMany(group => group.Rows).First().Address;

        Assert.Equal("https://app.example/#view=002", Opens("https://app.example/#view=002"));
        Assert.Equal("https://app.example/", Opens("https://app.example/"));
        Assert.Equal("https://www.example.org/wiki/Page#Geography", Opens("example.org/wiki/Page#Geography"));
        Assert.Equal("https://www.example.org/wiki/Page", Opens("example.org/wiki/Page"));
    }

    /// The row Return runs for each text typed into `RankingSpace`, with what
    /// the field completes: a word that names a site the field completes
    /// leads from two letters, as the tab on that site, an open one before a
    /// saved one however much more the saved one was used, and a word that
    /// starts a tab's title, or the site name its title ends with, from
    /// three. Every other text that names no address searches first: a single
    /// letter, a word followed by a space, a match inside a word or with its
    /// letters out of order, a phrase, a word further into a title, a page
    /// history knows only by its title, and a site visited too little to
    /// complete. An address, a partial one and a calculation lead as before.
    private static readonly Dictionary<string, (PaletteRowKind Kind, string? Title, string? Completes)> LeadingCases = new() {
        ["pa"] = (PaletteRowKind.Tab, "#general - Parlor", "parlor.example"),
        ["parl"] = (PaletteRowKind.Tab, "#general - Parlor", "parlor.example"),
        ["forge"] = (PaletteRowKind.Tab, "Pull requests · crest · Forge", "forge.example"),
        ["pull"] = (PaletteRowKind.Tab, "Pull requests · crest · Forge", null),
        ["mail"] = (PaletteRowKind.Tab, "Inbox (3) – Post", "mail.post.example"),
        ["inbox"] = (PaletteRowKind.Tab, "Inbox (3) – Post", null),
        ["post"] = (PaletteRowKind.Tab, "Inbox (3) – Post", null),
        ["cal"] = (PaletteRowKind.PinnedTab, "Calendar", "calendar.post.example"),
        ["meeting"] = (PaletteRowKind.SavedTab, "Meeting notes | Pages", null),
        ["news"] = (PaletteRowKind.OpenAddress, "Open news.example", "news.example"),
        ["crest"] = (PaletteRowKind.OpenAddress, "Open crest.example", "crest.example"),
        ["p"] = (PaletteRowKind.Search, null, null),
        ["pu"] = (PaletteRowKind.Search, null, null),
        ["po"] = (PaletteRowKind.Search, null, null),
        ["parl "] = (PaletteRowKind.Search, null, null),
        ["rlor"] = (PaletteRowKind.Search, null, null),
        ["pralor"] = (PaletteRowKind.Search, null, null),
        ["pull requests"] = (PaletteRowKind.Search, null, null),
        ["requests"] = (PaletteRowKind.Search, null, null),
        ["notes"] = (PaletteRowKind.Search, null, null),
        ["tech"] = (PaletteRowKind.Search, null, null),
        ["weather"] = (PaletteRowKind.Search, null, null),
        ["crest browser"] = (PaletteRowKind.Search, null, null),
        ["crest.ex"] = (PaletteRowKind.OpenAddress, "Open crest.example", "crest.example"),
        ["localhost:3000"] = (PaletteRowKind.OpenAddress, "Open localhost", null),
        ["24 * 7"] = (PaletteRowKind.Calculation, "168", null)
    };

    public static TheoryData<string> LeadingTexts { get; } = [.. LeadingCases.Keys];

    [Theory]
    [MemberData(nameof(LeadingTexts))]
    public void AWordThatNamesAPlaceLeadsWhileOtherTextSearchesFirst(string text) {
        var (session, space, shown) = RankingSpace();
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));
        var answer = device.Query(Asking(window, text));
        var first = answer.Groups.SelectMany(group => group.Rows).First();
        var (kind, title, completes) = LeadingCases[text];

        Assert.Equal((kind, title ?? first.Title, completes), (first.Kind, first.Title, answer.Completion?.Accepted));
    }

    /// Text that searches first still lists what matches it below the
    /// search, a word whose completion the person deleted searches too, and
    /// `localhost:3000` opens as typed.
    [Fact]
    public void SearchingTextStillListsItsMatchesAndADeletedCompletionSearches() {
        var (session, space, shown) = RankingSpace();
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));
        IReadOnlyList<PaletteRow> Rows(PaletteSuggestions question) => [.. device.Query(question).Groups.SelectMany(group => group.Rows)];

        var phrase = Rows(Asking(window, "crest browser"));
        Assert.Equal(PaletteRowKind.Search, phrase[0].Kind);
        Assert.Contains(phrase, row => row.Kind == PaletteRowKind.History && row.Title == "Crest Browser Notes");
        var deleted = Rows(Asking(window, "parl") with { AllowsCompletion = false });
        Assert.Equal(PaletteRowKind.Search, deleted[0].Kind);
        Assert.Contains(deleted, row => row.Kind == PaletteRowKind.Tab && row.Title == "#general - Parlor");
        Assert.Equal("http://localhost:3000", Rows(Asking(window, "localhost:3000"))[0].Address);
    }

    [Fact]
    public void StoredPalettePreferencesNameEveryKindOnceAndKeepWhatTheyCannotRead() {
        var stored = JsonNode.Parse("""
            {"layout":"spiral","showsTopHit":false,"sources":[
              {"source":"history","isEnabled":false,"limit":12},{"source":"history","isEnabled":true},{"source":"telepathy"},
              {"source":"openTabs","isEnabled":true,"limit":0}]}
            """);

        var preferences = StoredSessionCodec.DecodePalettePreferences(stored);

        Assert.Equal((PaletteLayout.Sections, false), (preferences.Layout, preferences.ShowsTopHit));
        // A number of rows outside what a person may choose is the kind's own.
        Assert.Equal((12, PaletteSection.Tabs.Limit), (preferences.Limit(PaletteSource.History), preferences.Limit(PaletteSource.OpenTabs)));
        Assert.Equal(PaletteSource.All.Count, preferences.Sources.Count);
        Assert.Equal([PaletteSource.History, PaletteSource.OpenTabs], preferences.Sources.Take(2).Select(choice => choice.Source));
        Assert.False(preferences.Offers(PaletteSource.History));
        Assert.Equal(PaletteSource.ArchivedTabs.IsEnabledByDefault, preferences.Offers(PaletteSource.ArchivedTabs));
        Assert.Equal(preferences, StoredSessionCodec.DecodePalettePreferences(StoredSessionCodec.Encode(preferences)));
    }

    /// A saved session with only `tabs` and `history` in its one Space, each
    /// history entry first and last visited that many days ago.
    private static (JsonNode Session, Guid Space) PaletteSession(JsonNode[] tabs,
        params (string Url, string Title, int Visits, double FirstDaysAgo, double LastDaysAgo)[] history) {
        var (document, space, _) = SavedSession();
        var saved = document["session"]!["spaces"]![0]!;
        saved["tabs"] = new JsonArray(tabs);
        saved["folders"] = new JsonArray();
        saved.AsObject().Remove("selectedTabID");
        double now = (DateTimeOffset.UtcNow - StoredSessionCodec.ReferenceEpoch).TotalSeconds;
        saved["history"] = new JsonArray([.. history.OrderBy(entry => entry.LastDaysAgo).Select(entry => (JsonNode)new JsonObject {
            ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(),
            ["url"] = entry.Url,
            ["title"] = entry.Title,
            ["firstVisitedAt"] = now - entry.FirstDaysAgo * 86_400,
            ["lastVisitedAt"] = now - entry.LastDaysAgo * 86_400,
            ["visitCount"] = entry.Visits
        })]);
        return (document["session"]!, space);
    }

    /// A Space showing a home page, with open tabs on a chat, a code forge and
    /// a mail site, a pinned calendar, saved meeting notes and the forge's
    /// settings, saved and used more than its open tab, and a history the
    /// palette has no memory of yet: the chat, a news site and the forge's
    /// settings visited often, an article about the chat once, Crest's notes
    /// twelve times and a weather site three times. Answers the session, the
    /// Space and the tab it shows.
    private static (JsonNode Session, Guid Space, Guid Shown) RankingSpace() {
        Guid shown = Guid.NewGuid();
        JsonObject Tab(Guid id, string title, string url, string placement, double hoursAgo) {
            var tab = OpenTab(id, title, url);
            tab["placement"] = placement;
            tab["lastActivatedAt"] = (DateTimeOffset.UtcNow.AddHours(-hoursAgo) - StoredSessionCodec.ReferenceEpoch).TotalSeconds;
            if (placement != "current") tab["savedURL"] = url;
            return tab;
        }
        var (session, space) = PaletteSession([
                Tab(shown, "Home", "https://home.example/", "current", 0),
                Tab(Guid.NewGuid(), "#general - Parlor", "https://parlor.example/channels/1/2", "current", 3),
                Tab(Guid.NewGuid(), "Pull requests · crest · Forge", "https://forge.example/crest/pulls", "current", 0.3),
                Tab(Guid.NewGuid(), "Inbox (3) – Post", "https://mail.post.example/inbox", "current", 1),
                Tab(Guid.NewGuid(), "Calendar", "https://calendar.post.example/", "pinned", 30),
                Tab(Guid.NewGuid(), "Meeting notes | Pages", "https://pages.example/doc/1", "saved", 72),
                Tab(Guid.NewGuid(), "Settings | Forge", "https://forge.example/settings", "saved", 0.05)
            ],
            ("https://parlor.example/channels/1/2", "#general - Parlor", 40, 60, 0.1),
            ("https://wiki.example/Parlor", "Parlor - Wiki", 1, 3, 3),
            ("https://news.example/", "Tech Digest", 50, 100, 0.2),
            ("https://crest.example/notes", "Crest Browser Notes", 12, 40, 1),
            ("https://weather.example/", "Weather Forecast", 3, 9, 2),
            ("https://forge.example/settings", "Settings | Forge", 30, 60, 0.05));
        return (session, space, shown);
    }

    /// An open tab showing `url`, last used a week ago.
    private static JsonObject OpenTab(Guid id, string title, string url) => new() {
        ["id"] = SwiftId(id),
        ["title"] = title,
        ["url"] = url,
        ["placement"] = "current",
        ["symbol"] = "globe",
        ["lastActivatedAt"] = (DateTimeOffset.UtcNow.AddDays(-7) - StoredSessionCodec.ReferenceEpoch).TotalSeconds
    };
}
