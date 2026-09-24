using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void OwnedHistoryVisitsPreserveIdentityAndStaleCommandsCannotReplaceNewerVisits() {
        var f = SavedSession(); var session = f.Document["session"]!;
        session["spaces"]![0]!["history"] = new JsonArray();
        var core = new NativeSessionAuthority(Bytes(session));
        byte[] Visit(string url, string title) => SpaceCommand(session, "history.visit", new() { ["url"] = url, ["title"] = title });
        var first = core.PrepareCommand(Visit("https://example.org/page#one", "First"));
        Assert.Empty(JsonNode.Parse(core.Checkpoint().Read(f.Space.ToString()))!.AsArray());
        first.Commit();
        var original = JsonNode.Parse(core.Checkpoint().Read(f.Space.ToString()))![0]!;
        var stale = core.PrepareCommand(Visit("https://example.org/page#two", "Stale"));
        core.PrepareCommand(Visit("https://example.org/page#three", "Latest")).Commit();
        AssertStale(stale.Commit);
        var entry = JsonNode.Parse(core.Checkpoint().Read(f.Space.ToString()))![0]!;
        Assert.Equal(original["id"]!.GetValue<string>(), entry["id"]!.GetValue<string>());
        Assert.Equal("https://example.org/page", entry["url"]!.GetValue<string>());
        Assert.Equal("Latest", entry["title"]!.GetValue<string>());
        Assert.Equal(2, entry["visitCount"]!.GetValue<int>());
        var wrong = JsonNode.Parse(Visit("https://example.org/", "Wrong profile"))!;
        wrong["profileId"] = Guid.NewGuid().ToString();
        Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(Bytes(wrong)));
        var skipped = core.PrepareCommand(Visit("crest://extensions", "Internal"));
        Assert.Empty(JsonNode.Parse(skipped.Output)!["changes"]!.AsArray());
    }

    /// A history entry last visited at `time`, in the stored date format.
    private static JsonObject Visit(double time, string url) => new() {
        ["id"] = Guid.NewGuid().ToString(),
        ["url"] = url,
        ["title"] = "Visit",
        ["firstVisitedAt"] = 0.0,
        ["lastVisitedAt"] = time,
        ["visitCount"] = 2
    };

    private static JsonArray SavedHistory(NativeSessionAuthority core, Guid space) => JsonNode.Parse(core.Checkpoint().Read(space.ToString()))!.AsArray();

    [Fact]
    public void HistoryRemovalUsesLastVisitsHalfOpenRangeAndAddressesWithoutTheirFragment() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        space["history"] = new JsonArray([.. new[] { 10.0, 20.0, 30.0 }.Select(time => (JsonNode)Visit(time, $"https://example.org/{time}"))]);
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        DateTimeOffset At(double seconds) => StoredSessionCodec.Date(seconds);

        Assert.IsType<InvalidDateRange>(Assert.Throws<Rejected>(() =>
            device.Send(new RemoveHistoryRange(device.Workspace, f.Space, At(30), At(10)))).Rejection);
        device.Send(new RemoveHistoryRange(device.Workspace, f.Space, At(10), At(30)));
        var retained = Assert.Single(SavedHistory(core, f.Space));
        Assert.Equal(30.0, retained!["lastVisitedAt"]!.GetValue<double>());
        device.Send(new RemoveHistoryAddress(device.Workspace, f.Space, "https://example.org/30#ignored"));
        Assert.Empty(SavedHistory(core, f.Space));

        space["history"] = new JsonArray(Visit(40, "https://example.org/40"));
        var cleared = new NativeSessionAuthority(Bytes(session));
        using var other = new TestDevice(cleared);
        Assert.IsType<UnknownSpace>(Assert.Throws<Rejected>(() => other.Send(new ClearHistory(other.Workspace, Guid.NewGuid()))).Rejection);
        other.Send(new ClearHistory(other.Workspace, f.Space));
        Assert.Empty(SavedHistory(cleared, f.Space));
    }

    [Fact]
    public void RestoringAnArchivedTabReopensItByIdentityAndShowsItOnce() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!.DeepClone(); var id = Guid.NewGuid(); tab["id"] = SwiftId(id);
        space["archivedTabs"] = new JsonArray(new JsonObject { ["tab"] = tab, ["archivedAt"] = 0.0, ["reason"] = "closed" });
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var window = device.Showing(session);

        device.Send(new RestoreArchivedTab(device.Workspace, window, f.Space, id));

        var saved = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!;
        var restored = saved["tabs"]!.AsArray().Single(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>()) == id)!;
        Assert.Equal("current", restored["placement"]!.GetValue<string>());
        Assert.Null(restored["folderID"]); Assert.Null(restored["splitGroupID"]);
        Assert.True(JsonNode.DeepEquals(tab["iconAccent"], restored["iconAccent"]));
        Assert.Empty(saved["archivedTabs"]!.AsArray());
        Assert.Equal(id, device.Tab(window, f.Space));
        Assert.Equal(id, Assert.IsType<UnknownArchivedTab>(Assert.Throws<Rejected>(() =>
            device.Send(new RestoreArchivedTab(device.Workspace, window, f.Space, id))).Rejection).TabId);
    }

    [Fact]
    public void ArchiveRetentionRemovesOnlyTheExpiredOccurrenceOfALegacyRepeatedIdentity() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!.DeepClone(); tab["id"] = SwiftId(Guid.NewGuid());
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["archive"] = "oneDay" };
        space["archivedTabs"] = new JsonArray(
            new JsonObject { ["tab"] = tab.DeepClone(), ["archivedAt"] = 0.0, ["reason"] = "closed" },
            new JsonObject { ["tab"] = tab.DeepClone(), ["archivedAt"] = 900000.0, ["reason"] = "closed" });
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        device.Clock.Now = StoredSessionCodec.Date(900001.0);

        device.Send(new SweepExpiredRecords(device.Workspace));

        var saved = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!["archivedTabs"]!;
        Assert.Equal(900000.0, Assert.Single(saved.AsArray())!["archivedAt"]!.GetValue<double>());
    }

    [Fact]
    public void ASweepArchivesUnusedTabsAndExpiresRecordsButKeepsWhatWindowsShow() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var current = space["tabs"]![0]!.DeepClone(); var currentId = Guid.NewGuid(); current["id"] = SwiftId(currentId);
        current["placement"] = "current"; current["folderID"] = null; current["splitGroupID"] = null; current["lastActivatedAt"] = 0.0;
        space["tabs"]!.AsArray().Add(current);
        space["browsingPreferences"]!["currentTabCleanupPolicy"] = "after12Hours";
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneDay", ["archive"] = "oneDay" };
        space["history"] = new JsonArray(Visit(0, "https://example.com/old"));
        space["archivedTabs"] = new JsonArray();
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var window = device.Showing(session);
        var shown = device.Shown(window);
        device.Clock.Now = StoredSessionCodec.Date(800000100);

        device.Send(new SweepExpiredRecords(device.Workspace));

        var saved = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!;
        // The tab the window shows survives the sweep, and the window keeps showing it.
        Assert.Single(saved["tabs"]!.AsArray());
        Assert.Equal(shown, device.Shown(window));
        Assert.Equal(currentId, Guid.Parse(Assert.Single(saved["archivedTabs"]!.AsArray())!["tab"]!["id"]!["rawValue"]!.GetValue<string>()));
        Assert.Empty(SavedHistory(core, f.Space));
    }

    [Fact]
    public void ASweepWithinAMinuteOfTheLastDoesNothingUnlessRetentionChanged() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneWeek" };
        space["history"] = new JsonArray();
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        const double start = 800000000, day = 86400;
        void SweepAt(double seconds) {
            device.Clock.Now = StoredSessionCodec.Date(seconds);
            device.Send(new SweepExpiredRecords(device.Workspace));
        }
        SweepAt(start);

        core.Commit(FirstVisitDelta(space, Visit(start - 8 * day, "https://example.org/expired")));
        SweepAt(start + 59);
        Assert.Single(SavedHistory(core, f.Space));
        SweepAt(start + 60);
        Assert.Empty(SavedHistory(core, f.Space));

        // Shortening retention lets the next sweep apply it straight away.
        core.Commit(FirstVisitDelta(space, Visit(start - 2 * day, "https://example.org/recent")));
        var shorter = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!.DeepClone().AsObject();
        shorter["browsingPreferences"]!["dataRetention"]!["history"] = "oneDay";
        core.Commit(Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject { ["id"] = shorter["id"]!.DeepClone(), ["metadata"] = shorter })
        }));
        SweepAt(start + 61);
        Assert.Empty(SavedHistory(core, f.Space));
    }

    /// A value edit that records `entry` in the empty history of `space`.
    private static byte[] FirstVisitDelta(JsonNode space, JsonObject entry) => Bytes(new JsonObject {
        ["version"] = 1,
        ["spaces"] = new JsonArray(new JsonObject {
            ["id"] = space["id"]!.DeepClone(),
            ["history"] = new JsonObject {
                ["remove"] = new JsonArray(),
                ["upsert"] = new JsonArray(entry),
                ["order"] = new JsonArray(entry["id"]!.DeepClone())
            }
        })
    });

    [Fact]
    public void SplitIdentityEditsKeepIndependentFieldClocksAndRejectMissingGroups() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var first = space["tabs"]![0]!; var group = Guid.Parse(first["splitGroupID"]!["rawValue"]!.GetValue<string>());
        var second = first.DeepClone(); second["id"] = SwiftId(Guid.NewGuid()); space["tabs"]!.AsArray().Add(second);
        space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = SwiftId(group), ["customIconSymbol"] = "crest.emoji:🌊", ["iconModifiedAt"] = 123.0 });
        var core = new NativeSessionAuthority(Bytes(session));
        core.PrepareCommand(SpaceCommand(session, "split.title", new() { ["groupId"] = group.ToString(), ["value"] = "  Research  " })).Commit();
        var metadata = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!["splitGroups"]![0]!;
        Assert.Equal("Research", metadata["customTitle"]!.GetValue<string>());
        Assert.Equal(123.0, metadata["iconModifiedAt"]!.GetValue<double>());
        Assert.Equal("crest.emoji:🌊", metadata["customIconSymbol"]!.GetValue<string>());
        Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(SpaceCommand(session, "split.title",
            new() { ["groupId"] = Guid.NewGuid().ToString(), ["value"] = "Invalid" })));
    }
}
