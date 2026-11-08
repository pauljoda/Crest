using System.Text.Json.Nodes;

using CrestCore.Application;

using Xunit;

using static CrestCore.Application.ContentFilter;

namespace CrestCore.Tests;

/// What the compiled filter lists decide for a page's requests, which every
/// engine enforces and nothing on screen reveals when it is wrong.
public sealed class ContentFilterTests {
    private const string Page = "https://news.example/story";

    private static ContentFilterSlot SlotWith(params string[] lists) {
        var slot = new ContentFilterSlot();
        using var filter = Compile(lists);
        slot.Install(filter);
        return slot;
    }

    private static Request Image(string url, string page = Page) => new(url, page, RequestKind.Image);

    [Fact]
    public void ExceptionsImportantAndBadfiltersDecideTogetherAcrossLists() {
        using var slot = SlotWith(
            "||ads.example^\n||track.example^$important\n||pixel.example^\n||widgets.example^",
            "@@||ads.example/allowed^\n@@||track.example^\n||pixel.example^$badfilter");

        Assert.True(slot.Blocks(Image("https://ads.example/banner.png")));
        Assert.False(slot.Blocks(Image("https://ads.example/allowed/banner.png")));
        Assert.True(slot.Blocks(Image("https://track.example/p.gif")));
        Assert.False(slot.Blocks(Image("https://pixel.example/p.gif")));
        Assert.True(slot.Blocks(Image("https://cdn.widgets.example/w.png")));
    }

    [Fact]
    public void PartyDomainAndTypeOptionsScopeAFilter() {
        using var slot = SlotWith("||cdn.example^$third-party,script\n||social.example^$domain=news.example");

        Assert.True(slot.Blocks(new Request("https://cdn.example/lib.js", Page, RequestKind.Script)));
        Assert.False(slot.Blocks(new Request("https://cdn.example/lib.js", "https://cdn.example/", RequestKind.Script)));
        Assert.False(slot.Blocks(Image("https://cdn.example/logo.png")));
        Assert.True(slot.Blocks(Image("https://social.example/like.png")));
        Assert.False(slot.Blocks(Image("https://social.example/like.png", "https://blog.example/")));
    }

    [Fact]
    public void AFilterThatWouldServeAReplacementAllowsTheRequest() {
        using var slot = SlotWith("||tags.example/gtm.js$script,redirect=googletagmanager_gtm.js\n||tags.example/pixel.gif");

        Assert.False(slot.Blocks(new Request("https://tags.example/gtm.js", Page, RequestKind.Script)));
        Assert.True(slot.Blocks(Image("https://tags.example/pixel.gif")));
    }

    [Fact]
    public void ASlotKeepsItsFilterAndSwapsWhole() {
        using var slot = new ContentFilterSlot();
        Assert.False(slot.Blocks(Image("https://ads.example/banner.png")));

        using (var first = Compile(["||ads.example^"])) slot.Install(first);
        Assert.True(slot.Blocks(Image("https://ads.example/banner.png")));

        using (var second = Compile(["||track.example^"])) slot.Install(second);
        Assert.False(slot.Blocks(Image("https://ads.example/banner.png")));
        Assert.True(slot.Blocks(Image("https://track.example/p.gif")));

        slot.Install(null);
        Assert.False(slot.Blocks(Image("https://track.example/p.gif")));
    }

    [Fact]
    public void ASavedFilterLoadsWithTheSameDecisionsAndDamageIsRefused() {
        byte[] saved;
        using (var filter = Compile(["||track.example^\n@@||track.example/ok^"])) saved = filter.Save();

        using (var loaded = Load(saved)) {
            Assert.NotNull(loaded);
            using var slot = new ContentFilterSlot();
            slot.Install(loaded);
            Assert.True(slot.Blocks(Image("https://track.example/p.gif")));
            Assert.False(slot.Blocks(Image("https://track.example/ok/p.gif")));
        }

        var damaged = saved.ToArray();
        damaged[^1] ^= 0xFF;
        Assert.Null(Load(damaged));
    }

    [Fact]
    public void ContentRulesKeepExceptionsApartFromTheRulesTheyUndo() {
        var rules = ContentRulesFor(["||track.example^\nnews.example##.sponsored", "@@||track.example/ok^"]);
        static string Action(string rule) => JsonNode.Parse(rule)!["action"]!["type"]!.GetValue<string>();

        Assert.Contains(rules.Rules, rule => Action(rule) == "block");
        Assert.Contains(rules.Rules, rule => Action(rule) == "css-display-none");
        Assert.NotEmpty(rules.Exceptions);
        Assert.All(rules.Exceptions, rule => Assert.Equal("ignore-previous-rules", Action(rule)));
        Assert.DoesNotContain(rules.Rules, rule => Action(rule) == "ignore-previous-rules");
    }
}
