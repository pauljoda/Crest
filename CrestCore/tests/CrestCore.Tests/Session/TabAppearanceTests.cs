using System.Text.Json.Nodes;

using CrestCore.Application;

using Xunit;

namespace CrestCore.Tests;

/// A tab's icon, the page it is showing and the page it belongs to are decided
/// once, here. The image bytes stay in the native cache; these edits only name
/// the tab whose stored image the platform must replace or drop.
public sealed partial class BrowserContractsTests {
    private static JsonNode Edited(JsonNode space, string operation, JsonObject arguments)
        => JsonNode.Parse(NativeSessionEditor.Evaluate(EditRequest(space, operation, arguments)))!;

    private static JsonNode Tab(JsonNode result) => result["space"]!["tabs"]![0]!;

    [Fact]
    public void AChosenIconSurvivesPageObservationsAndHandingItBackRestoresTheAutomaticOne() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!;
        var tabId = fixture.Tab.ToString();
        // The fixture tab wears an emoji and stores no mode, so its mode comes
        // from its own symbol: an observed favicon must not displace it.
        var observed = Edited(space, "tab.observe", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://example.com/article#two",
            ["title"] = "Later title",
            ["hasFavicon"] = true,
            ["faviconChanged"] = true,
            ["iconAccent"] = new JsonObject { ["red"] = 0.5 }
        });
        Assert.True(observed["changed"]!.GetValue<bool>());
        Assert.Null(observed["favicon"]);
        Assert.Equal("crest.emoji:🌊", Tab(observed)["symbol"]!.GetValue<string>());
        Assert.Equal("https://example.com/favicon.ico", Tab(observed)["faviconURL"]!.GetValue<string>());
        Assert.Equal("Later title", Tab(observed)["title"]!.GetValue<string>());

        // A blank page title is the page saying nothing, not a request to clear.
        var blank = Edited(observed["space"]!, "tab.observe", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://example.com/article#two",
            ["title"] = ""
        });
        Assert.Equal("Later title", Tab(blank)["title"]!.GetValue<string>());

        // Nothing new to report at all is not a revision.
        var unchanged = Edited(observed["space"]!, "tab.observe", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://example.com/article#two",
            ["title"] = "Later title",
            ["hasFavicon"] = true,
            ["faviconChanged"] = false
        });
        Assert.False(unchanged["changed"]!.GetValue<bool>());

        var cleared = Edited(observed["space"]!, "tab.icon", new JsonObject { ["tabId"] = tabId, ["mode"] = "automatic" });
        Assert.Equal("globe", Tab(cleared)["symbol"]!.GetValue<string>());
        Assert.Equal("automatic", Tab(cleared)["storedIconMode"]!.GetValue<string>());
        Assert.Null(Tab(cleared)["faviconURL"]);
        Assert.Null(Tab(cleared)["iconAccent"]);
        Assert.False(cleared["favicon"]!["adopts"]!.GetValue<bool>());

        var adopted = Edited(cleared["space"]!, "tab.observe", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://example.com/article#two",
            ["title"] = "Later title",
            ["hasFavicon"] = true,
            ["faviconChanged"] = true,
            ["iconAccent"] = new JsonObject { ["red"] = 0.5 }
        });
        Assert.True(adopted["favicon"]!["adopts"]!.GetValue<bool>());
        Assert.Equal(tabId.ToUpperInvariant(), adopted["favicon"]!["tabId"]!.GetValue<string>().ToUpperInvariant());
        Assert.Equal("https://example.com/article#two", Tab(adopted)["faviconURL"]!.GetValue<string>());

        // Pulling an icon by hand pins the tab to it, so the next page keeps it.
        var pulled = Edited(adopted["space"]!, "tab.icon", new JsonObject {
            ["tabId"] = tabId,
            ["mode"] = "pulled",
            ["hasFavicon"] = true
        });
        Assert.Equal("pulled", Tab(pulled)["storedIconMode"]!.GetValue<string>());
        var moved = Edited(pulled["space"]!, "tab.observe", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://elsewhere.example/page",
            ["title"] = "Elsewhere",
            ["hasFavicon"] = true,
            ["faviconChanged"] = true
        });
        Assert.Null(moved["favicon"]);
        Assert.Equal("https://example.com/article#two", Tab(moved)["faviconURL"]!.GetValue<string>());
    }

    [Fact]
    public void AnAutomaticFaviconIsAdoptedOnlyForThePageTheTabIsStillShowing() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!;
        var tabId = fixture.Tab.ToString();
        var automatic = Edited(space, "tab.icon", new JsonObject { ["tabId"] = tabId, ["mode"] = "automatic" })["space"]!;

        // The tab shows ".../article#one". A fragment is not another page, so a
        // favicon captured for ".../article" belongs to what the tab is showing.
        var same = Edited(automatic, "tab.favicon.cache", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://example.com/article",
            ["hasFavicon"] = true
        });
        Assert.True(same["changed"]!.GetValue<bool>());
        Assert.True(same["favicon"]!["adopts"]!.GetValue<bool>());
        Assert.Equal("https://example.com/article", Tab(same)["faviconURL"]!.GetValue<string>());

        var different = Edited(automatic, "tab.favicon.cache", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://example.com/other",
            ["hasFavicon"] = true
        });
        Assert.False(different["changed"]!.GetValue<bool>());
        Assert.Null(different["favicon"]);

        // A chosen icon is never replaced by a late capture either.
        var emoji = Edited(space, "tab.icon", new JsonObject {
            ["tabId"] = tabId,
            ["mode"] = "emoji",
            ["emoji"] = "📚"
        });
        Assert.Equal("crest.emoji:📚", Tab(emoji)["symbol"]!.GetValue<string>());
        var late = Edited(emoji["space"]!, "tab.favicon.cache", new JsonObject {
            ["tabId"] = tabId,
            ["url"] = "https://example.com/article",
            ["hasFavicon"] = true
        });
        Assert.False(late["changed"]!.GetValue<bool>());
    }

    [Fact]
    public void ASavedTabCanAdoptThePageItIsShowingOrReturnToTheOneItBelongsTo() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!;
        var tabId = fixture.Tab.ToString();

        var restored = Edited(space, "tab.saved_location", new JsonObject { ["tabId"] = tabId, ["action"] = "restore" });
        Assert.True(restored["changed"]!.GetValue<bool>());
        Assert.Equal("https://example.com/", Tab(restored)["url"]!.GetValue<string>());
        // Already home, so there is nothing to adopt.
        Assert.False(Edited(restored["space"]!, "tab.saved_location",
            new JsonObject { ["tabId"] = tabId, ["action"] = "replace" })["changed"]!.GetValue<bool>());

        var adopted = Edited(space, "tab.saved_location", new JsonObject { ["tabId"] = tabId, ["action"] = "replace" });
        Assert.True(adopted["changed"]!.GetValue<bool>());
        Assert.Equal("https://example.com/article#one", Tab(adopted)["savedURL"]!.GetValue<string>());

        // A current tab is wherever browsing took it; it belongs nowhere.
        var current = space.DeepClone();
        current["tabs"]![0]!["placement"] = "current";
        current["tabs"]![0]!["savedURL"] = null;
        foreach (var action in new[] { "replace", "restore" })
            Assert.False(Edited(current, "tab.saved_location",
                new JsonObject { ["tabId"] = tabId, ["action"] = action })["changed"]!.GetValue<bool>());
    }

    [Fact]
    public void CreatingAFolderAroundTabsFilesThemInTheSameTransaction() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!.DeepClone();
        space["tabs"]![0]!["folderID"] = null;
        space["tabs"]![0]!["splitGroupID"] = null;
        var folderId = Guid.NewGuid();
        var result = Edited(space, "folder.create", new JsonObject {
            ["folderId"] = folderId.ToString(),
            ["placement"] = "saved",
            ["tabIds"] = new JsonArray(fixture.Tab.ToString()),
            ["detach"] = false
        });
        var created = result["space"]!["folders"]!.AsArray().Single(f => Guid.Parse(f!["id"]!["rawValue"]!.GetValue<string>()) == folderId);
        Assert.Equal("New Folder", created!["title"]!.GetValue<string>());
        Assert.Equal(folderId, Guid.Parse(Tab(result)["folderID"]!["rawValue"]!.GetValue<string>()));
    }
}
