using System.Collections.Concurrent;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What the device subscribes to, when each list is downloaded again, and the
/// content rules WebKit compiles from them: a wrong answer blocks nothing, or
/// too much, without anything on screen saying so.
public sealed class FilterLibraryTests {
    private static readonly DateTimeOffset Start = new(2026, 11, 7, 12, 0, 0, TimeSpan.Zero);

    private sealed class Library {
        public readonly TestClock Clock = new(Start);
        public readonly Dictionary<FilterList, bool> Choices = [];
        public readonly BlockingCollection<ContentRuleListSet> Announced = new();
        public readonly FilterLibrary Filters;

        public Library(IReadOnlyList<string>? languages = null, DevicePlatform? platform = null) {
            Filters = new(null, platform ?? DevicePlatform.Desktop, languages ?? ["en-US"], () => Choices, change => {
                if (change is ContentRuleListsChanged changed) Announced.Add(changed.Lists);
            }, Clock);
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
        bool IsOn(Library library, FilterList list) => library.Filters.States().Single(state => state.List == list).IsOn;

        Assert.True(IsOn(german, FilterList.EasyListGermany));
        Assert.True(IsOn(german, FilterList.EasyList));
        Assert.False(IsOn(german, FilterList.ListeFr));
        Assert.False(IsOn(german, FilterList.EasyListCookie));
        Assert.False(IsOn(new Library(["en-GB"]), FilterList.EasyListGermany));

        german.Choices[FilterList.EasyListGermany] = false;
        german.Choices[FilterList.EasyListCookie] = true;
        Assert.False(IsOn(german, FilterList.EasyListGermany));
        Assert.True(IsOn(german, FilterList.EasyListCookie));
        Assert.DoesNotContain(german.Filters.Due(), fetch => fetch.List == FilterList.EasyListGermany);
    }

    [Fact]
    public void ListsAreDueUntilDownloadedThenWhenTheyExpireAndFailuresBackOff() {
        var library = new Library();
        var changes = new ChangeFeed();
        var due = library.Filters.Due();
        Assert.Equal(FilterList.All.Where(list => list.IsDefault), due.Select(fetch => fetch.List));
        Assert.All(due, fetch => Assert.Null(fetch.EntityTag));
        // What was handed out is not handed out again at once.
        Assert.Empty(library.Filters.Due());

        library.Filters.Fetched(FilterList.EasyList, "! Expires: 1 day\n||ads.example^", "\"v1\"", null, changes);
        library.Filters.Failed(FilterList.EasyPrivacy, changes);
        library.Clock.Now = Start + TimeSpan.FromMinutes(31);
        var retried = library.Filters.Due();
        Assert.Contains(retried, fetch => fetch.List == FilterList.EasyPrivacy);
        Assert.DoesNotContain(retried, fetch => fetch.List == FilterList.EasyList);
        Assert.True(library.Filters.States().Single(state => state.List == FilterList.EasyPrivacy).IsFailing);

        // A list that asks for a day is kept at least twelve hours and asked
        // for again within a tenth past its day, with its validators.
        library.Clock.Now = Start + TimeSpan.FromHours(23);
        Assert.DoesNotContain(library.Filters.Due(), fetch => fetch.List == FilterList.EasyList);
        library.Clock.Now = Start + TimeSpan.FromHours(27);
        var again = Assert.Single(library.Filters.Due(), fetch => fetch.List == FilterList.EasyList);
        Assert.Equal("\"v1\"", again.EntityTag);

        library.Filters.NotModified(FilterList.EasyList, changes);
        Assert.Equal(library.Clock.Now, library.Filters.States().Single(state => state.List == FilterList.EasyList).UpdatedAt);
        Assert.Throws<Rejected>(() => library.Filters.Fetched(FilterList.EasyList,
            new string('x', FilterLibrary.MaximumListBytes + 1), null, null, changes));
    }

    [Fact]
    public void TheBaselineBlocksUntilListsArriveAndEveryCompiledListEndsWithTheExceptions() {
        var library = new Library();
        Assert.Empty(library.Filters.Rules().Identifiers);
        var baseline = library.NextRules();
        Assert.Equal(baseline, library.Filters.Rules());
        var baselineRules = library.Rules(Assert.Single(baseline.Identifiers));
        Assert.Contains(baselineRules, rule => Action(rule) == "block"
            && rule["trigger"]!["url-filter"]!.GetValue<string>().Contains("doubleclick", StringComparison.Ordinal));

        // Enough rules for three compiled lists, and exceptions that undo
        // rules wherever those rules land.
        var list = new StringBuilder("! Title: Large\n");
        for (int index = 0; index < 150_000; index++) list.Append("||host").Append(index).Append(".example^\n");
        list.Append("@@||host1.example/allowed^\n@@||host149999.example/allowed^\n");
        library.Filters.Fetched(FilterList.EasyList, list.ToString(), null, null, new ChangeFeed());
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
        Assert.Equal(150_000 + baselineRules.Count(rule => Action(rule) != "ignore-previous-rules"), compiled.Sum(rulesOfList => rulesOfList.Count - exceptions));
        Assert.Throws<Rejected>(() => library.Filters.Source(baseline.Identifiers[0]));

        // Turning the list off brings back the baseline rules.
        library.Choices[FilterList.EasyList] = false;
        library.Filters.SubscriptionsChanged(new ChangeFeed());
        Assert.Single(library.NextRules().Identifiers);
    }
}
