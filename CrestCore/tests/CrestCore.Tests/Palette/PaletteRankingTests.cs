using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// How the palette decides what leads and in what order: inline completion
/// follows other browsers and Return opens what the field shows, text that
/// names no address searches first, a typed fragment survives, a place shows
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

    /// Return searches any text that names no address, a single word too,
    /// however strongly a known page matches it, and the field completes
    /// none of it; an address, a partial one the field completes and a
    /// calculation still lead.
    [Fact]
    public void TextThatNamesNoAddressSearchesFirstWhileAnAddressStillOpens() {
        var (session, space) = PaletteSession([], ("https://crest.example/notes", "Crest Browser Notes", 12, 40, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);
        (PaletteRow First, AddressCompletion? Completion, IReadOnlyList<PaletteRow> Rows) Asked(string text) {
            var answer = device.Query(Asking(window, text));
            var rows = answer.Groups.SelectMany(group => group.Rows).ToList();
            return (rows[0], answer.Completion, rows);
        }

        foreach (var text in new[] { "crest browser", "crest" }) {
            var searched = Asked(text);
            Assert.Equal((PaletteRowKind.Search, (AddressCompletion?)null), (searched.First.Kind, searched.Completion));
            Assert.Contains(searched.Rows, row => row.Kind == PaletteRowKind.History && row.Title == "Crest Browser Notes");
        }
        var partial = Asked("crest.ex");
        Assert.Equal(("crest.example", PaletteRowKind.OpenAddress), (partial.Completion?.Accepted, partial.First.Kind));
        Assert.Equal(("http://localhost:3000", PaletteRowKind.OpenAddress), (Asked("localhost:3000").First.Address,
            Asked("localhost:3000").First.Kind));
        Assert.Equal(PaletteRowKind.Calculation, Asked("24 * 7").First.Kind);
    }

    /// A history row names the tabs whose icon it may wear for its site, best
    /// first: tabs on its page, whatever their fragment, archived ones too,
    /// then the rest of the site, `www.` aside. A tab on another port or
    /// another site is never one.
    [Fact]
    public void AHistoryRowWearsTheIconOfATabOnItsPageFirstThenOfItsSite() {
        Guid samePage = Guid.NewGuid(), sameSite = Guid.NewGuid(), otherPort = Guid.NewGuid(), otherSite = Guid.NewGuid();
        var (session, space) = PaletteSession(
            [OpenTab(sameSite, "Pears", "https://www.orchard.example/pears"), OpenTab(otherPort, "Apples", "https://orchard.example:8443/apples"),
                OpenTab(otherSite, "Apples", "https://harbor.example/apples")],
            ("https://orchard.example/apples", "Orchard Apples", 3, 2, 1));
        session["spaces"]![0]!["archivedTabs"] = new JsonArray(new JsonObject {
            ["tab"] = OpenTab(samePage, "Apples", "https://orchard.example/apples#core"),
            ["reason"] = "closed",
            ["archivedAt"] = (DateTimeOffset.UtcNow.AddHours(-1) - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds
        });
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var history = device.Query(Asking(window, "orchard apples")).Groups.SelectMany(group => group.Rows)
            .First(row => row.Kind == PaletteRowKind.History);
        Assert.Equal([samePage, sameSite], history.IconTabIds);
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
        double now = (DateTimeOffset.UtcNow - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds;
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

    /// An open tab showing `url`, last used a week ago.
    private static JsonObject OpenTab(Guid id, string title, string url) => new() {
        ["id"] = SwiftId(id),
        ["title"] = title,
        ["url"] = url,
        ["placement"] = "current",
        ["symbol"] = "globe",
        ["lastActivatedAt"] = (DateTimeOffset.UtcNow.AddDays(-7) - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds
    };
}
