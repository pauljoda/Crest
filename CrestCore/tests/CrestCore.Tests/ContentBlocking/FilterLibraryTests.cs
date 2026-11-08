using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What the device subscribes to, when each list is downloaded again, and what
/// each engine enforces from them: the content rules WebKit compiles, and the
/// filter and hiding rules Chromium checks. A wrong answer blocks nothing, or
/// too much, without anything on screen saying so.
public sealed partial class FilterLibraryTests {
    private static readonly DateTimeOffset Start = new(2026, 11, 7, 12, 0, 0, TimeSpan.Zero);

    private sealed class Library {
        public readonly TestClock Clock = new(Start);
        public readonly Dictionary<FilterList, bool> Choices = [];
        public readonly List<CustomFilterList> CustomLists = [];
        public string CustomFilters = "";
        public readonly BlockingCollection<ContentRuleListSet> Announced = new();
        public readonly FilterLibrary Filters;

        public Library(IReadOnlyList<string>? languages = null, DevicePlatform? platform = null, string? resourcesDigest = null) {
            Filters = new(null, platform ?? DevicePlatform.Desktop, languages ?? ["en-US"], () => new Device.FilterPreferences(Choices, CustomLists, CustomFilters), change => {
                if (change is ContentRuleListsChanged changed) Announced.Add(changed.Lists);
            }, Clock, resourcesDigest: resourcesDigest);
        }

        /// The rules announced next, which a worker converts.
        public ContentRuleListSet NextRules() {
            Assert.True(Announced.TryTake(out var rules, TimeSpan.FromSeconds(30)), "No content rules were announced.");
            return rules!;
        }

        public IReadOnlyList<JsonNode> Rules(string identifier) =>
            [.. JsonNode.Parse(Filters.Source(identifier).Source)!.AsArray().Select(rule => rule!)];
    }

    private static string Action(JsonNode rule) => rule["action"]!["type"]!.GetValue<string>();

    /// The check the Chromium engine calls with the slot's address.
    [LibraryImport("crest_content_filter")]
    private static unsafe partial int crest_content_filter_slot_check(nint slot,
        ContentFilterLibrary.Request* request, ContentFilterLibrary.Decision* decision);

    private static unsafe bool SlotBlocks(nint slot, string url, string page) {
        byte[] urlBytes = Encoding.UTF8.GetBytes(url), pageBytes = Encoding.UTF8.GetBytes(page);
        ContentFilterLibrary.Decision decision = default;
        fixed (byte* urlPointer = urlBytes)
        fixed (byte* pagePointer = pageBytes) {
            var request = new ContentFilterLibrary.Request {
                Url = new() { Bytes = urlPointer, Length = (nuint)urlBytes.Length },
                SourceUrl = new() { Bytes = pagePointer, Length = (nuint)pageBytes.Length },
                Kind = (byte)ContentFilter.RequestKind.Script,
                Method = (byte)ContentFilter.RequestMethod.Get
            };
            Assert.Equal(ContentFilterLibrary.Ok, crest_content_filter_slot_check(slot, &request, &decision));
        }
        return decision.Verdict == ContentFilterLibrary.Block;
    }

    [Fact]
    public void ConditionalBlocksResolveForThePlatformAndTheHeaderSaysWhenAListExpires() {
        var text = new FilterListText("""
            [Adblock Plus 2.0]
            ! Title: Sample
            ! Expires: 5 days (update frequency)
            ||always.example^
            !#if env_safari
            ||safari.example^
            !#if !env_mobile
            ||desktop-safari.example^
            !#else
            ||mobile-safari.example^
            !#endif
            !#else
            ||not-safari.example^
            !#endif
            !#if (env_chromium || env_edge) && !false
            ||chromium.example^
            !#endif
            !#if cap_html_filtering
            example.com##^script
            !#endif
            !#include filters-2026.txt
            """);

        string desktop = text.Resolved(new HashSet<string> { "env_safari" });
        Assert.Equal(["||always.example^", "||safari.example^", "||desktop-safari.example^"],
            desktop.Split('\n', StringSplitOptions.RemoveEmptyEntries).Where(line => line.StartsWith("||", StringComparison.Ordinal)));
        Assert.Contains("||mobile-safari.example^", text.Resolved(new HashSet<string> { "env_safari", "env_mobile" }));
        Assert.Contains("||chromium.example^", text.Resolved(new HashSet<string> { "env_chromium" }));
        Assert.Contains("||not-safari.example^", text.Resolved(new HashSet<string> { "env_chromium" }));
        Assert.DoesNotContain("!#include", desktop);
        Assert.DoesNotContain("^script", desktop);
        Assert.Equal(TimeSpan.FromDays(5), text.Expiry());
        Assert.Equal(TimeSpan.FromHours(8), new FilterListText("! Expires: 8 hours\n||a.example^").Expiry());
        Assert.Null(new FilterListText("! Expires: 40 days\n||a.example^").Expiry());
        Assert.Null(new FilterListText("||a.example^\n! Expires: 1 day").Expiry());
    }

    [Fact]
    public void RegionalListsFollowTheLanguagesUntilThePersonChooses() {
        var german = new Library(["de-DE", "en-US"]);
        bool IsOn(Library library, FilterList list) => library.Filters.States().Lists.Single(state => state.List == list).IsOn;

        Assert.True(IsOn(german, FilterList.EasyListGermany));
        Assert.True(IsOn(german, FilterList.EasyList));
        Assert.False(IsOn(german, FilterList.ListeFr));
        Assert.False(IsOn(german, FilterList.EasyListCookie));
        Assert.False(IsOn(new Library(["en-GB"]), FilterList.EasyListGermany));

        german.Choices[FilterList.EasyListGermany] = false;
        german.Choices[FilterList.EasyListCookie] = true;
        Assert.False(IsOn(german, FilterList.EasyListGermany));
        Assert.True(IsOn(german, FilterList.EasyListCookie));
        Assert.DoesNotContain(german.Filters.Due(), fetch => fetch.Id == FilterLibrary.IdOf(FilterList.EasyListGermany));
    }

    [Fact]
    public void ListsAreDueUntilDownloadedThenWhenTheyExpireAndFailuresBackOff() {
        var library = new Library();
        var due = library.Filters.Due();
        Assert.Equal([.. FilterList.All.Where(list => list.IsDefault).Select(FilterLibrary.IdOf), FilterLibrary.ResourcesId], due.Select(fetch => fetch.Id));
        Assert.Equal(FilterLibrary.PublishedResourcesUrl, due[^1].Url);
        Assert.All(due, fetch => Assert.Null(fetch.EntityTag));
        // What was handed out is not handed out again at once.
        Assert.Empty(library.Filters.Due());

        library.Filters.Fetched(FilterLibrary.IdOf(FilterList.EasyList), "! Expires: 1 day\n||ads.example^", "\"v1\"", null);
        library.Filters.Failed(FilterLibrary.IdOf(FilterList.EasyPrivacy));
        library.Clock.Now = Start + TimeSpan.FromMinutes(31);
        var retried = library.Filters.Due();
        Assert.Contains(retried, fetch => fetch.Id == FilterLibrary.IdOf(FilterList.EasyPrivacy));
        Assert.DoesNotContain(retried, fetch => fetch.Id == FilterLibrary.IdOf(FilterList.EasyList));
        Assert.True(library.Filters.States().Lists.Single(state => state.List == FilterList.EasyPrivacy).IsFailing);

        // A list that asks for a day is kept at least twelve hours and asked
        // for again within a tenth past its day, with its validators.
        library.Clock.Now = Start + TimeSpan.FromHours(23);
        Assert.DoesNotContain(library.Filters.Due(), fetch => fetch.Id == FilterLibrary.IdOf(FilterList.EasyList));
        library.Clock.Now = Start + TimeSpan.FromHours(27);
        var again = Assert.Single(library.Filters.Due(), fetch => fetch.Id == FilterLibrary.IdOf(FilterList.EasyList));
        Assert.Equal("\"v1\"", again.EntityTag);

        library.Filters.NotModified(FilterLibrary.IdOf(FilterList.EasyList));
        Assert.Equal(library.Clock.Now, library.Filters.States().Lists.Single(state => state.List == FilterList.EasyList).UpdatedAt);
        // A copy too large to use is refused; the one the device holds stays.
        var held = library.Filters.States().Lists.Single(state => state.List == FilterList.EasyList).UpdatedAt;
        library.Filters.Fetched(FilterLibrary.IdOf(FilterList.EasyList), new string('x', FilterLibrary.MaximumListBytes + 1),
            null, null);
        var refused = library.Filters.States().Lists.Single(state => state.List == FilterList.EasyList);
        Assert.True(refused.IsFailing);
        Assert.Equal(held, refused.UpdatedAt);
    }

    [Fact]
    public void TheBaselineBlocksUntilListsArriveAndEveryCompiledListEndsWithTheExceptions() {
        var library = new Library();
        // The baseline converts on a worker as the library starts: until then
        // there are no rules, and after it the baseline is what is in force.
        var before = library.Filters.Rules();
        var baseline = library.NextRules();
        Assert.True(before.Identifiers.Count == 0 || before == baseline);
        Assert.Equal(baseline, library.Filters.Rules());
        var baselineRules = library.Rules(Assert.Single(baseline.Identifiers));
        Assert.Contains(baselineRules, rule => Action(rule) == "block"
            && rule["trigger"]!["url-filter"]!.GetValue<string>().Contains("doubleclick", StringComparison.Ordinal));

        // Enough rules for three compiled lists, exceptions that undo rules
        // wherever those rules land, and a generic and a site hiding rule.
        var list = new StringBuilder("! Title: Large\n");
        for (int index = 0; index < 150_000; index++) list.Append("||host").Append(index).Append(".example^\n");
        list.Append("@@||host1.example/allowed^\n@@||host149999.example/allowed^\n##.generic-ad\nnews.example##.site-ad\n");
        library.Filters.Fetched(FilterLibrary.IdOf(FilterList.EasyList), list.ToString(), null, null);
        var rules = library.NextRules();

        Assert.Equal(3, rules.Identifiers.Count);
        Assert.DoesNotContain(baseline.Identifiers[0], rules.Identifiers);
        var compiled = rules.Identifiers.Select(library.Rules).ToList();
        Assert.All(compiled, rulesOfList => Assert.InRange(rulesOfList.Count, 1, 150_000));
        int exceptions = compiled[0].Count(rule => Action(rule) == "ignore-previous-rules");
        Assert.True(exceptions >= 2);
        Assert.All(compiled, rulesOfList => {
            Assert.All(rulesOfList.TakeLast(exceptions), rule => Assert.Equal("ignore-previous-rules", Action(rule)));
            Assert.DoesNotContain(rulesOfList.SkipLast(exceptions), rule => Action(rule) == "ignore-previous-rules");
        });
        Assert.Equal(150_001 + baselineRules.Count(rule => Action(rule) != "ignore-previous-rules"), compiled.Sum(rulesOfList => rulesOfList.Count - exceptions));
        Assert.Throws<Rejected>(() => library.Filters.Source(baseline.Identifiers[0]));
        // Generic hiding goes through the cosmetic bridge, never into the
        // compiled lists, where it would apply before a page first renders.
        Assert.All(compiled, rulesOfList => Assert.DoesNotContain(rulesOfList,
            rule => Action(rule) == "css-display-none" && rule["trigger"]!["if-domain"] is null));

        // Turning the list off brings back the baseline rules.
        library.Choices[FilterList.EasyList] = false;
        library.Filters.SubscriptionsChanged();
        Assert.Single(library.NextRules().Identifiers);
    }

    [Fact]
    public void TheCompiledFilterReachesTheSlotAndAnswersWhatADocumentHidesAndCollapses() {
        var library = new Library();
        library.Filters.Fetched(FilterLibrary.IdOf(FilterList.EasyList), """
            ! Title: Chromium
            ||ads.example^
            @@||ads.example/allowed^
            !#if env_chromium
            ||chromium-ads.example^
            ##.chromium-only
            !#endif
            !#if env_safari
            ||safari-ads.example^
            ##.safari-only
            !#endif
            ##.ad-banner
            ###sponsor
            news.example##.site-ad
            news.example#@#.ad-banner
            news.example#?#.card:has-text(Advertisement)
            news.example##.promo:style(height: 0)
            """, null, null);

        // The library compiles the filter on a worker as the lists change,
        // before any engine asks for the slot; the slot it then makes holds it
        // from the start.
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(30);
        while (library.Filters.Cosmetics("https://other.example/", true, ["ad-banner"], [], []).Style.Length == 0) {
            Assert.True(DateTime.UtcNow < deadline, "The filter never compiled.");
            Thread.Sleep(20);
        }
        nint slot = library.Filters.SlotAddress();
        Assert.NotEqual(0, slot);
        Assert.True(SlotBlocks(slot, "https://ads.example/tag.js", "https://other.example/"));
        Assert.Equal(slot, library.Filters.SlotAddress());
        Assert.False(SlotBlocks(slot, "https://ads.example/allowed/tag.js", "https://other.example/"));
        Assert.True(SlotBlocks(slot, "https://chromium-ads.example/tag.js", "https://other.example/"));
        Assert.False(SlotBlocks(slot, "https://safari-ads.example/tag.js", "https://other.example/"));
        Assert.True(SlotBlocks(slot, "https://doubleclick.net/tag.js", "https://other.example/"));

        // Style rules: the generic rules for what the document shows, less the
        // site's exceptions, and the site's own rules on the first ask only.
        var elsewhere = library.Filters.Cosmetics("https://other.example/", first: true,
            ["ad-banner", "chromium-only", "safari-only", "article"], ["sponsor"], []);
        Assert.True(elsewhere.Blocks);
        Assert.Contains(".ad-banner{display:none!important}", elsewhere.Style);
        Assert.Contains(".chromium-only{display:none!important}", elsewhere.Style);
        Assert.Contains("#sponsor{display:none!important}", elsewhere.Style);
        Assert.DoesNotContain(".safari-only", elsewhere.Style);
        Assert.DoesNotContain(".article", elsewhere.Style);
        Assert.DoesNotContain(".site-ad", elsewhere.Style);
        Assert.Empty(elsewhere.Procedural);

        var onSite = library.Filters.Cosmetics("https://news.example/story", first: true, ["ad-banner"], [], []);
        Assert.Contains(".site-ad{display:none!important}", onSite.Style);
        Assert.DoesNotContain(".ad-banner", onSite.Style);
        Assert.Contains(onSite.Procedural, filter => filter.Contains("has-text", StringComparison.Ordinal)
            && filter.Contains("Advertisement", StringComparison.Ordinal));
        Assert.Contains(onSite.Procedural, filter => filter.Contains("\"style\"", StringComparison.Ordinal));
        var later = library.Filters.Cosmetics("https://news.example/story", first: false, [], [], []);
        Assert.Equal("", later.Style);
        Assert.Empty(later.Procedural);

        // Elements whose loads the filter blocks collapse.
        var collapsed = library.Filters.Cosmetics("https://news.example/story", first: false, [], [],
            [new PageResource(PageResourceKind.Frame, "https://ads.example/frame.html"),
             new PageResource(PageResourceKind.Image, "https://ads.example/allowed/pixel.png"),
             new PageResource(PageResourceKind.Image, "https://cdn.example/photo.jpg")]);
        Assert.Equal(["https://ads.example/frame.html"], collapsed.Collapse);
    }

    [Fact]
    public void AListThePersonAddedAndTheirOwnFiltersApplyLikeAnyList() {
        var library = new Library();
        var added = new CustomFilterList(Guid.NewGuid(), "https://lists.example/mine.txt", IsOn: true);
        library.CustomLists.Add(added);
        var due = library.Filters.Due();
        Assert.Contains(due, fetch => fetch.Id == added.Id && fetch.Url == added.Url);
        var state = Assert.Single(library.Filters.States().CustomLists);
        Assert.Equal("lists.example", state.Title);

        // One with more rules than the core takes is too large to use.
        library.Filters.Fetched(added.Id, string.Concat(Enumerable.Repeat("||x.example^\n", FilterLibrary.MaximumListRules + 1)),
            null, null);
        Assert.True(Assert.Single(library.Filters.States().CustomLists).IsTooLarge);
        library.Filters.Fetched(added.Id, "! Title: Mine\n||mine-ads.example^\n", null, null);
        Assert.Equal("Mine", Assert.Single(library.Filters.States().CustomLists).Title);
        Assert.False(Assert.Single(library.Filters.States().CustomLists).IsTooLarge);
        library.CustomFilters = "||own-ads.example^\nnews.example##.own-box";
        library.Filters.SubscriptionsChanged();

        nint slot = library.Filters.SlotAddress();
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(30);
        while (!SlotBlocks(slot, "https://own-ads.example/tag.js", "https://other.example/")) {
            Assert.True(DateTime.UtcNow < deadline, "The person's own filters never reached the filter.");
            Thread.Sleep(20);
        }
        Assert.True(SlotBlocks(slot, "https://mine-ads.example/tag.js", "https://other.example/"));
        Assert.Contains(".own-box{display:none!important}",
            library.Filters.Cosmetics("https://news.example/", first: true, [], [], []).Style);

        // Turned off, the added list stops applying; removed, it goes.
        library.CustomLists[0] = added with { IsOn = false };
        library.Filters.SubscriptionsChanged();
        while (SlotBlocks(slot, "https://mine-ads.example/tag.js", "https://other.example/")) {
            Assert.True(DateTime.UtcNow < deadline + TimeSpan.FromSeconds(30), "The list turned off kept applying.");
            Thread.Sleep(20);
        }
        Assert.DoesNotContain(library.Filters.Due(), fetch => fetch.Id == added.Id);
        library.CustomLists.Clear();
        library.Filters.SubscriptionsChanged();
        Assert.Empty(library.Filters.States().CustomLists);
    }

    [Fact]
    public void ScriptletsRunFromTheResourcesTheFilterLoads() {
        const string resources = """
            [{"name":"set-constant.js","aliases":["set.js"],"kind":{"mime":"application/javascript"},
              "content":"ZnVuY3Rpb24gc2V0Q29uc3RhbnQoYSwgYikgeyB3aW5kb3dbYV0gPSBiOyB9"}]
            """;
        var library = new Library(resourcesDigest: DigestOf(resources));
        library.Filters.Fetched(FilterLibrary.IdOf(FilterList.EasyList), "news.example##+js(set, adsOff, true)\n||ads.example^",
            null, null);
        Assert.Equal("", library.Filters.Scriptlets("https://news.example/"));
        library.Filters.Fetched(FilterLibrary.ResourcesId, resources, null, null);
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(30);
        while (!library.Filters.Scriptlets("https://news.example/").Contains("setConstant(", StringComparison.Ordinal)) {
            Assert.True(DateTime.UtcNow < deadline, "The scriptlets never came with the resources.");
            Thread.Sleep(20);
        }
        Assert.Contains("adsOff", library.Filters.Scriptlets("https://news.example/"));
        Assert.Equal("", library.Filters.Scriptlets("https://other.example/"));
    }

    /// Scriptlets run code in pages, so the core loads resources only with the
    /// digest it pins, and a copy with any other is refused and fetched again.
    [Fact]
    public void ResourcesOtherThanThePinnedOnesAreRefused() {
        const string resources = """
            [{"name":"set-constant.js","aliases":["set.js"],"kind":{"mime":"application/javascript"},
              "content":"ZnVuY3Rpb24gc2V0Q29uc3RhbnQoYSwgYikgeyB3aW5kb3dbYV0gPSBiOyB9"}]
            """;
        var library = new Library(resourcesDigest: DigestOf(resources));
        library.Filters.Fetched(FilterLibrary.IdOf(FilterList.EasyList), "news.example##+js(set, adsOff, true)", null, null);
        library.Filters.Fetched(FilterLibrary.ResourcesId, resources.Replace("adsOff", "other", StringComparison.Ordinal) + " ",
            null, null);
        Thread.Sleep(500);
        Assert.Equal("", library.Filters.Scriptlets("https://news.example/"));
        library.Clock.Now += TimeSpan.FromDays(1);
        var again = Assert.Single(library.Filters.Due(), fetch => fetch.Id == FilterLibrary.ResourcesId);
        Assert.Null(again.EntityTag);
    }

    /// uBlock keeps some scriptlets for trusted lists: the catalog's lists may
    /// run them, a list the person added and their own filters may not.
    [Fact]
    public void OnlyTheCatalogsListsRunTrustedScriptlets() {
        const string resources = """
            [{"name":"trusted-set-constant.js","aliases":["trusted-set.js"],"kind":{"mime":"application/javascript"},
              "content":"ZnVuY3Rpb24gdHJ1c3RlZFNldChhLCBiKSB7IHdpbmRvd1thXSA9IGI7IH0=","permission":1}]
            """;
        var library = new Library(resourcesDigest: DigestOf(resources));
        var added = new CustomFilterList(Guid.NewGuid(), "https://lists.example/mine.txt", IsOn: true);
        library.CustomLists.Add(added);
        library.CustomFilters = "own.example##+js(trusted-set, fromOwn, 1)";
        library.Filters.Fetched(FilterLibrary.IdOf(FilterList.EasyList), "chosen.example##+js(trusted-set, fromChosen, 1)",
            null, null);
        library.Filters.Fetched(added.Id, "added.example##+js(trusted-set, fromAdded, 1)", null, null);
        library.Filters.Fetched(FilterLibrary.ResourcesId, resources, null, null);
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(30);
        while (!library.Filters.Scriptlets("https://chosen.example/").Contains("fromChosen", StringComparison.Ordinal)) {
            Assert.True(DateTime.UtcNow < deadline, "The catalog's trusted scriptlet never ran.");
            Thread.Sleep(20);
        }
        Assert.DoesNotContain("fromAdded", library.Filters.Scriptlets("https://added.example/"));
        Assert.DoesNotContain("fromOwn", library.Filters.Scriptlets("https://own.example/"));
    }

    private static string DigestOf(string text) =>
        Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text)));

}
