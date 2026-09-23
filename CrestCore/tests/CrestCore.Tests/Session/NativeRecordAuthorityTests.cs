using System.Text.Json.Nodes;

using CrestCore.Application;
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
        var first = core.PrepareCommand(1, Visit("https://example.org/page#one", "First"));
        Assert.Empty(JsonNode.Parse(core.Checkpoint(1).Read(f.Space.ToString()))!.AsArray());
        first.Commit();
        var original = JsonNode.Parse(core.Checkpoint(2).Read(f.Space.ToString()))![0]!;
        var stale = core.PrepareCommand(2, Visit("https://example.org/page#two", "Stale"));
        core.PrepareCommand(2, Visit("https://example.org/page#three", "Latest")).Commit();
        Assert.Throws<BrowserRuleException>(() => stale.Commit());
        var entry = JsonNode.Parse(core.Checkpoint(3).Read(f.Space.ToString()))![0]!;
        Assert.Equal(original["id"]!.GetValue<string>(), entry["id"]!.GetValue<string>());
        Assert.Equal("https://example.org/page", entry["url"]!.GetValue<string>());
        Assert.Equal("Latest", entry["title"]!.GetValue<string>());
        Assert.Equal(2, entry["visitCount"]!.GetValue<int>());
        var wrong = JsonNode.Parse(Visit("https://example.org/", "Wrong profile"))!;
        wrong["profileId"] = Guid.NewGuid().ToString();
        Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(3, Bytes(wrong)));
        var skipped = core.PrepareCommand(3, Visit("crest://extensions", "Internal"));
        Assert.Empty(JsonNode.Parse(skipped.Output)!["changes"]!.AsArray());
    }

    [Fact]
    public void OwnedHistoryDeletionUsesLastVisitHalfOpenRangeAndCancelledStoragePreservesHistory() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        space["history"] = new JsonArray(new[] { 10.0, 20.0, 30.0 }.Select(time => (JsonNode)new JsonObject {
            ["id"] = Guid.NewGuid().ToString(),
            ["url"] = $"https://example.org/{time}",
            ["title"] = "Visit",
            ["firstVisitedAt"] = 0.0,
            ["lastVisitedAt"] = time,
            ["visitCount"] = 2
        }).ToArray());
        var core = new NativeSessionAuthority(Bytes(session));
        var before = core.Checkpoint(1).Read(f.Space.ToString());
        var clear = core.PrepareCommand(1, SpaceCommand(session, "history.clear", new()));
        using (clear.Reserve()) { }
        Assert.Equal(before, core.Checkpoint(1).Read(f.Space.ToString()));
        core.PrepareCommand(1, SpaceCommand(session, "history.remove_range", new() { ["start"] = 10.0, ["end"] = 30.0 })).Commit();
        var retained = JsonNode.Parse(core.Checkpoint(2).Read(f.Space.ToString()))!.AsArray();
        Assert.Single(retained); Assert.Equal(30.0, retained[0]!["lastVisitedAt"]!.GetValue<double>());
        core.PrepareCommand(2, SpaceCommand(session, "history.remove_url", new() { ["url"] = "https://example.org/30#ignored" })).Commit();
        Assert.Empty(JsonNode.Parse(core.Checkpoint(3).Read(f.Space.ToString()))!.AsArray());
    }

    [Fact]
    public void ArchiveRestoreReadsTheOwnedRecordAndCannotRestoreItTwice() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!.DeepClone(); var id = Guid.NewGuid(); tab["id"] = SwiftId(id);
        space["archivedTabs"] = new JsonArray(new JsonObject { ["tab"] = tab, ["archivedAt"] = 0.0, ["reason"] = "closed" });
        var core = new NativeSessionAuthority(Bytes(session));
        var request = SpaceCommand(session, "archive.restore", new() { ["tabId"] = id.ToString() });
        var command = core.PrepareCommand(1, request); command.Commit();
        var result = JsonNode.Parse(command.Output)!["changes"]![0]!["tabEdit"]!["space"]!;
        var restored = result["tabs"]!.AsArray().Single(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>()) == id)!;
        Assert.Equal("current", restored["placement"]!.GetValue<string>());
        Assert.Null(restored["folderID"]); Assert.Null(restored["splitGroupID"]);
        Assert.True(JsonNode.DeepEquals(tab["futureTabProperty"], restored["futureTabProperty"]));
        Assert.Empty(JsonNode.Parse(core.Checkpoint(2).Read("core"))!["spaces"]![0]!["archivedTabs"]!.AsArray());
        Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(2, request));
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
        var request = JsonNode.Parse(SpaceCommand(session, "records.sweep", new()))!;
        request["now"] = 900001.0;
        var command = core.PrepareCommand(1, Bytes(request)); command.Commit();
        var output = JsonNode.Parse(command.Output)!["changes"]![0]!["removedArchiveIndices"]!;
        Assert.Equal(0, Assert.Single(output.AsArray())!.GetValue<int>());
        var saved = JsonNode.Parse(core.Checkpoint(2).Read("core"))!["spaces"]![0]!["archivedTabs"]!;
        Assert.Equal(900000.0, Assert.Single(saved.AsArray())!["archivedAt"]!.GetValue<double>());
    }

    [Fact]
    public void OwnedCleanupPreservesSelectionAndUsesCoreRetentionPreferences() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var current = space["tabs"]![0]!.DeepClone(); var currentId = Guid.NewGuid(); current["id"] = SwiftId(currentId);
        current["placement"] = "current"; current["folderID"] = null; current["splitGroupID"] = null; current["lastActivatedAt"] = 0.0;
        space["tabs"]!.AsArray().Add(current);
        space["browsingPreferences"]!["currentTabCleanupPolicy"] = "after12Hours";
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneDay", ["archive"] = "oneDay" };
        space["history"] = new JsonArray(new JsonObject { ["id"] = Guid.NewGuid().ToString(), ["lastVisitedAt"] = 0.0 });
        space["archivedTabs"] = new JsonArray();
        var core = new NativeSessionAuthority(Bytes(session));
        var command = core.PrepareCommand(1, SpaceCommand(session, "records.sweep", new()));
        command.Commit();
        var saved = JsonNode.Parse(core.Checkpoint(2).Read("core"))!["spaces"]![0]!;
        // The tab the window shows survives the sweep, and nothing asks the
        // window to change what it shows.
        Assert.Single(saved["tabs"]!.AsArray());
        Assert.True(LeavesSelection(JsonNode.Parse(command.Output)!));
        Assert.Null(saved["selectedTabID"]);
        Assert.Single(saved["archivedTabs"]!.AsArray());
        Assert.Equal(currentId, Guid.Parse(saved["archivedTabs"]![0]!["tab"]!["id"]!["rawValue"]!.GetValue<string>()));
        Assert.Empty(JsonNode.Parse(core.Checkpoint(2).Read(f.Space.ToString()))!.AsArray());
        Assert.Empty(JsonNode.Parse(core.PrepareCommand(2, SpaceCommand(session, "records.sweep", new())).Output)!["changes"]!.AsArray());
    }

    [Fact]
    public void SplitIdentityEditsKeepIndependentFieldClocksAndRejectMissingGroups() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var first = space["tabs"]![0]!; var group = Guid.Parse(first["splitGroupID"]!["rawValue"]!.GetValue<string>());
        var second = first.DeepClone(); second["id"] = SwiftId(Guid.NewGuid()); space["tabs"]!.AsArray().Add(second);
        space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = SwiftId(group), ["customIconSymbol"] = "crest.emoji:🌊", ["iconModifiedAt"] = 123.0 });
        var core = new NativeSessionAuthority(Bytes(session));
        core.PrepareCommand(1, SpaceCommand(session, "split.title", new() { ["groupId"] = group.ToString(), ["value"] = "  Research  " })).Commit();
        var metadata = JsonNode.Parse(core.Checkpoint(2).Read("core"))!["spaces"]![0]!["splitGroups"]![0]!;
        Assert.Equal("Research", metadata["customTitle"]!.GetValue<string>());
        Assert.Equal(123.0, metadata["iconModifiedAt"]!.GetValue<double>());
        Assert.Equal("crest.emoji:🌊", metadata["customIconSymbol"]!.GetValue<string>());
        Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(2, SpaceCommand(session, "split.title",
            new() { ["groupId"] = Guid.NewGuid().ToString(), ["value"] = "Invalid" })));
    }
}
