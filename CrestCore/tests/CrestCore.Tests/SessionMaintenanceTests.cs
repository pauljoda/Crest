using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    [Fact]
    public void SessionRepairIsAtomicPreservesAdditiveFieldsAndReidentifiesRuntimeCollisions()
    {
        var source = SavedSession().Document["session"]!.AsObject();
        var first = source["spaces"]![0]!;
        source["futureSessionIntent"] = new JsonObject { ["enabled"] = true };
        var second = first.DeepClone();
        first["tabs"]![0]!["futureTabIntent"] = "preserved";
        source["spaces"]!.AsArray().Add(second);
        var before = Bytes(source);
        var output = NativeSessionMaintenance.Repair(source, 800000000);
        var result = output["session"]!;
        Assert.Equal(before, Bytes(source));
        Assert.True(result["futureSessionIntent"]!["enabled"]!.GetValue<bool>());
        Assert.Equal("preserved", result["spaces"]![0]!["tabs"]![0]!["futureTabIntent"]!.GetValue<string>());
        Assert.NotEqual(result["spaces"]![0]!["id"]!.ToJsonString(), result["spaces"]![1]!["id"]!.ToJsonString());
        Assert.NotEqual(result["spaces"]![0]!["profile"]!["id"]!.ToJsonString(), result["spaces"]![1]!["profile"]!["id"]!.ToJsonString());
        Assert.NotEqual(result["spaces"]![0]!["tabs"]![0]!["id"]!.ToJsonString(), result["spaces"]![1]!["tabs"]![0]!["id"]!.ToJsonString());
        Assert.Equal(1, output["assets"]!.AsArray().Last()!["spaceIndex"]!.GetValue<int>());
        Assert.True(JsonNode.DeepEquals(result, NativeSessionMaintenance.Repair(result.AsObject(), 800000001)["session"]));
    }

    [Fact]
    public void FailedRetentionLeavesEveryCategoryAndTheSourceUnchanged()
    {
        var source = SavedSession().Document["session"]!.AsObject(); var space = source["spaces"]![0]!;
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneDay", ["archive"] = "oneDay" };
        space["history"] = new JsonArray(new JsonObject { ["lastVisitedAt"] = 0.0 });
        space["archivedTabs"] = new JsonArray(new JsonObject { ["archivedAt"] = "invalid" });
        var before = Bytes(source);
        Assert.Throws<InvalidOperationException>(() => NativeSessionMaintenance.Retain(source, 800000000));
        Assert.Equal(before, Bytes(source));
        space["archivedTabs"] = new JsonArray();
        var retained = NativeSessionMaintenance.Retain(source, 800000000);
        Assert.True(retained["changed"]!.GetValue<bool>());
        Assert.Empty(retained["session"]!["spaces"]![0]!["history"]!.AsArray());
        Assert.Single(space["history"]!.AsArray());
    }

    [Fact]
    public void PreparedSyncFailureCannotAdvanceTheJournalAfterLocalStaging()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var initial = JournalDocument(SyncTabRecord(fixture.Tab.Value, fixture.Space.Value, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial)); var before = journal.Read().ToArray();
        var space = NativeSyncProjection.Project(session, SyncProjectionPreferences(), [])
            .Single(n => n!["type"]!.GetValue<string>() == "space")!;
        space["value"]!["profileID"] = Guid.NewGuid().ToString("D");
        var incoming = new JsonObject { ["id"] = new JsonObject { ["kind"] = "space", ["value"] = fixture.Space.Value.ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space.Value), ["payload"] = space.DeepClone(),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") } };
        var request = new JsonObject { ["version"] = 1, ["operation"] = "merge", ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(), ["records"] = new JsonArray(incoming), ["now"] = 800000000.0 };
        var error = Assert.Throws<NativeSyncDocumentException>(() => NativeSyncSessionTransition.Prepare(journal, Bytes(request)));
        Assert.Equal("immutableProfileChanged", error.Code);
        Assert.Equal(before, journal.Read());
    }

    [Fact]
    public void ReplacingASeedWithCloudProducesAMatchedNonDisposableSessionAndJournal()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var initial = JournalDocument(SyncTabRecord(fixture.Tab.Value, fixture.Space.Value, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial));
        var staged = journal.Apply(JournalCommand(initial, "stage", new JsonObject
        { ["session"] = session.DeepClone(), ["deletionReason"] = "superseded", ["now"] = 800000000.0 }));
        var records = JsonNode.Parse(staged.Read())!["records"]!.DeepClone();
        session["disposableSeedMarker"] = Guid.NewGuid().ToString("D");
        var transition = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject
        { ["version"] = 1, ["operation"] = "replace", ["session"] = session.DeepClone(), ["preferences"] = SyncProjectionPreferences(),
            ["records"] = records, ["now"] = 800000000.0 }));
        var result = transition.Materialization["session"]!.AsObject();
        Assert.Null(result["disposableSeedMarker"]);
        var payloads = NativeSyncProjection.Project(result, SyncProjectionPreferences(),
            JsonNode.Parse(transition.Journal.Read())!["records"]!.AsArray().Select(n => n!.AsObject()));
        Assert.Equal(new[] { "folder", "history", "space", "tab" },
            payloads.Select(p => p!["type"]!.GetValue<string>()).Order(StringComparer.Ordinal));
        Assert.Empty(JsonNode.Parse(transition.Journal.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.NotNull(session["disposableSeedMarker"]);
    }

    [Fact]
    public void CloudReplacementCannotDiscardLocallyAuthorizedCleanup()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["spaceDeletions"] = new JsonArray(new JsonObject
        {
            ["spaceID"] = session["spaces"]![0]!["id"]!.DeepClone(),
            ["profileID"] = session["spaces"]![0]!["profile"]!["id"]!.DeepClone(),
            ["operationID"] = Guid.NewGuid().ToString("D")
        });
        var initial = JournalDocument(SyncTabRecord(fixture.Tab.Value, fixture.Space.Value, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial));
        var transition = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject
        {
            ["version"] = 1, ["operation"] = "replace", ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(), ["records"] = new JsonArray(), ["now"] = 800000000.0
        }));
        var result = transition.Materialization["session"]!;
        Assert.True(JsonNode.DeepEquals(session["spaceDeletions"], result["spaceDeletions"]));
        Assert.Equal(2, result["spaces"]!.AsArray().Count);
        var kept = result["spaces"]!.AsArray().Single(s => JsonNode.DeepEquals(s!["id"], session["spaces"]![0]!["id"]));
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0], kept));
        Assert.False(JsonNode.DeepEquals(result["selectedSpaceID"], kept!["id"]));
        var repaired = NativeSessionMaintenance.Repair(result.AsObject(), 800000000.0)["session"]!;
        Assert.True(JsonNode.DeepEquals(result["spaceDeletions"], repaired["spaceDeletions"]));
        var tombstone = new JsonObject
        {
            ["id"] = new JsonObject { ["kind"] = "space", ["value"] = fixture.Space.Value.ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space.Value),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") },
            ["tombstone"] = new JsonObject { ["reason"] = "explicitDelete", ["deletedAt"] = 800000000.0 }
        };
        var merged = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject
        {
            ["version"] = 1, ["operation"] = "merge", ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(), ["records"] = new JsonArray(tombstone), ["now"] = 800000000.0
        }));
        var record = JsonNode.Parse(merged.Journal.Read())!["records"]!.AsArray().Single(r =>
            r!["id"]!["kind"]!.GetValue<string>() == "space" && Guid.Parse(r["id"]!["value"]!.GetValue<string>()) == fixture.Space.Value)!;
        Assert.Equal("explicitDelete", record["tombstone"]!["reason"]!.GetValue<string>());
        Assert.Single(merged.Materialization["session"]!["spaceDeletions"]!.AsArray());
    }
}
