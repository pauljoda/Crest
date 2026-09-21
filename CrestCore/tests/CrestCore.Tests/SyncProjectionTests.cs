using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static JsonObject SyncProjectionPreferences(bool saved = true, bool current = true, bool history = true)
        => new() { ["savedStructure"] = saved, ["currentTabs"] = current, ["historyAndArchive"] = history };

    [Theory]
    [InlineData("https://example.com", true)]
    [InlineData("http://localhost:3200", true)]
    [InlineData("crest://extensions", false)]
    [InlineData("chrome://extensions", false)]
    [InlineData("chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html", false)]
    [InlineData("file:///tmp/page.html", false)]
    [InlineData("about:blank", false)]
    [InlineData(null, false)]
    public void OnlyPortableWebContentEntersSharedRecords(string? url, bool expected)
    {
        Assert.Equal(expected, SyncContentPolicy.IncludesTab(url, false, null));
        Assert.False(SyncContentPolicy.IncludesTab(url, true, null));
        Assert.False(SyncContentPolicy.IncludesTab(url, false, "crest://settings"));
    }

    [Fact]
    public void ProjectionPreservesWireMetadataButExcludesLocalAssetsAndDisabledCategories()
    {
        var session = SavedSession().Document["session"]!.AsObject(); var space = session["spaces"]![0]!;
        var original = space["tabs"]![0]!;
        original["faviconData"] = "local-image";
        var local = original.DeepClone(); local["id"] = SwiftId(Guid.NewGuid()); local["url"] = "crest://extensions/";
        space["tabs"]!.AsArray().Add(local);
        space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = original["splitGroupID"]!.DeepClone(), ["customTitle"] = "Research" });
        var result = NativeSyncProjection.Project(session, SyncProjectionPreferences(), []);
        var tab = Assert.Single(result, p => p!["type"]!.GetValue<string>() == "tab")!["value"]!;
        Assert.Equal("https://example.com/", tab["savedURL"]!.GetValue<string>());
        Assert.Null(tab["faviconData"]); Assert.Null(tab["faviconURL"]); Assert.Null(tab["iconAccent"]);
        var projectedSpace = result[0]!["value"]!;
        Assert.Null(projectedSpace["credentialPreferences"]);
        Assert.True(JsonNode.DeepEquals(space["branding"], projectedSpace["branding"]));
        Assert.True(JsonNode.DeepEquals(space["browsingPreferences"], projectedSpace["browsingPreferences"]));
        Assert.Single(projectedSpace["splitGroups"]!.AsArray());
        var disabled = NativeSyncProjection.Project(session, SyncProjectionPreferences(false, false, false), []);
        Assert.Single(disabled);
        // Group intent survives turning off tab categories on this device.
        Assert.Single(disabled[0]!["value"]!["splitGroups"]!.AsArray());
        Assert.Equal("local-image", original["faviconData"]!.GetValue<string>());
    }

    [Fact]
    public void ProjectionRetainsPositionsAndClearsArchivedMembershipWithoutChangingLocalAuditReason()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject(); var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!; tab.AsObject().Remove("savedURL");
        var record = SyncTabRecord(fixture.Tab.Value, fixture.Space.Value, 10, Guid.NewGuid());
        record["payload"]!["value"]!["orderToken"] = "3fffffffffffffff";
        space["archivedTabs"] = new JsonArray(new JsonObject
        { ["tab"] = tab.DeepClone(), ["archivedAt"] = 800000010.0, ["reason"] = "synced", ["deletionOrigin"] = "remote" });
        var result = NativeSyncProjection.Project(session, SyncProjectionPreferences(), [record]);
        var projectedTab = result.Single(p => p!["type"]!.GetValue<string>() == "tab")!["value"]!;
        Assert.Equal("3fffffffffffffff", projectedTab["orderToken"]!.GetValue<string>());
        Assert.Equal(tab["url"]!.GetValue<string>(), projectedTab["savedURL"]!.GetValue<string>());
        var archive = result.Single(p => p!["type"]!.GetValue<string>() == "archive")!["value"]!;
        Assert.Equal("deleted", archive["reason"]!.GetValue<string>());
        Assert.Equal("current", archive["tab"]!["placement"]!.GetValue<string>());
        Assert.Null(archive["tab"]!["folderID"]); Assert.Null(archive["tab"]!["splitGroupID"]); Assert.Null(archive["tab"]!["savedURL"]);
        Assert.Equal("remote", space["archivedTabs"]![0]!["deletionOrigin"]!.GetValue<string>());
    }

    [Fact]
    public void ReceivingArchivesDoesNotRewriteTheirCauseOrPositionsWhenRestaged()
    {
        var fixture = SavedSession(); var source = fixture.Document["session"]!.AsObject();
        var space = source["spaces"]![0]!; var template = space["tabs"]![0]!.DeepClone();
        source.Remove("disposableSeedMarker");
        space["tabs"] = new JsonArray(); space["folders"] = new JsonArray();
        space["history"] = new JsonArray(); space["selectedTabID"] = null;
        foreach (var (reason, index) in new[] { "autoCleanup", "quickWindow", "closed", "deleted" }.Select((r, i) => (r, i)))
        {
            var tab = template.DeepClone().AsObject(); tab["id"] = SwiftId(Guid.NewGuid());
            tab["placement"] = "current"; tab.Remove("savedURL"); tab.Remove("folderID"); tab.Remove("splitGroupID");
            space["archivedTabs"]!.AsArray().Add(new JsonObject { ["tab"] = tab,
                ["archivedAt"] = 800000001.0 + index, ["reason"] = reason });
        }
        var initial = JournalDocument(SyncTabRecord(fixture.Tab.Value, fixture.Space.Value, 1, Guid.NewGuid()));
        initial["records"] = new JsonArray(); initial["pendingRecordIDs"] = new JsonArray();
        byte[] Stage(JsonNode session) => JournalCommand(initial, "stage", new()
        { ["session"] = session.DeepClone(), ["deletionReason"] = "superseded", ["now"] = 800000100.0 });
        var sender = new NativeSyncJournal(Bytes(initial)).Apply(Stage(source));
        var sent = JsonNode.Parse(sender.Read())!;
        var seed = SavedSession().Document["session"]!.AsObject();
        var received = NativeSyncSessionTransition.Prepare(new NativeSyncJournal(Bytes(initial)), Bytes(new JsonObject
        {
            ["version"] = 1, ["operation"] = "replace", ["session"] = seed.DeepClone(),
            ["preferences"] = initial["preferences"]!.DeepClone(), ["records"] = sent["records"]!.DeepClone(),
            ["now"] = 800000100.0
        }));
        var materialized = received.Materialization["session"]!;
        Assert.All(materialized["spaces"]![0]!["archivedTabs"]!.AsArray(), a =>
            Assert.Equal("synced", a!["reason"]!.GetValue<string>()));
        var restaged = JsonNode.Parse(received.Journal.Apply(Stage(materialized)).Read())!;
        Assert.Empty(restaged["pendingRecordIDs"]!.AsArray());
        Assert.Equal(sent["logicalClock"]!.GetValue<ulong>(), restaged["logicalClock"]!.GetValue<ulong>());
        Assert.True(JsonNode.DeepEquals(sent["records"], restaged["records"]));
        var added = materialized["spaces"]![0]!["archivedTabs"]![0]!.DeepClone().AsObject();
        var addedId = Guid.NewGuid(); added["tab"]!["id"] = SwiftId(addedId);
        added["reason"] = "quickWindow"; added.Remove("deletionOrigin"); added["archivedAt"] = 800000101.0;
        materialized["spaces"]![0]!["archivedTabs"]!.AsArray().Insert(0, added);
        var updated = JsonNode.Parse(received.Journal.Apply(Stage(materialized)).Read())!;
        var pending = Assert.Single(updated["pendingRecordIDs"]!.AsArray())!;
        Assert.Equal(addedId, Guid.Parse(pending["value"]!.GetValue<string>()));
        var retained = updated["records"]!.AsArray().Where(r =>
            Guid.Parse(r!["id"]!["value"]!.GetValue<string>()) != addedId).Select(r => r!.DeepClone());
        Assert.True(JsonNode.DeepEquals(sent["records"], new JsonArray(retained.ToArray())));
    }

    [Fact]
    public void InvalidProjectionReportsTheOffendingIdentityWithoutMutatingTheSource()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var folder = session["spaces"]![0]!["folders"]![0]!;
        folder["parentID"] = folder["id"]!.DeepClone();
        var request = new JsonObject { ["version"] = 1, ["operation"] = "project", ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(), ["records"] = new JsonArray() };
        var input = Bytes(request);
        var result = JsonNode.Parse(NativeSyncQuery.Prepare(input))!;
        Assert.Equal("invalidFolderHierarchy", result["error"]!["code"]!.GetValue<string>());
        Assert.Equal(fixture.Space.Value.ToString("D"), result["error"]!["value"]!.GetValue<string>());
        Assert.Equal(input, Bytes(request));
    }
}
