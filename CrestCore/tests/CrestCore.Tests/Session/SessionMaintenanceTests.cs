using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void SessionRepairIsAtomicAndReidentifiesRuntimeCollisions() {
        var source = SavedSession().Document["session"]!.AsObject();
        source["spaces"]!.AsArray().Add(source["spaces"]![0]!.DeepClone());
        var before = Bytes(source);
        var output = NativeSessionMaintenance.Repair(source, 800000000);
        var result = output["session"]!;
        Assert.Equal(before, Bytes(source));
        Assert.NotEqual(result["spaces"]![0]!["id"]!.ToJsonString(), result["spaces"]![1]!["id"]!.ToJsonString());
        Assert.NotEqual(result["spaces"]![0]!["profile"]!["id"]!.ToJsonString(), result["spaces"]![1]!["profile"]!["id"]!.ToJsonString());
        Assert.NotEqual(result["spaces"]![0]!["tabs"]![0]!["id"]!.ToJsonString(), result["spaces"]![1]!["tabs"]![0]!["id"]!.ToJsonString());
        Assert.Equal(1, output["assets"]!.AsArray().Last()!["spaceIndex"]!.GetValue<int>());
        Assert.True(JsonNode.DeepEquals(result, NativeSessionMaintenance.Repair(result.AsObject(), 800000001)["session"]));
    }

    [Fact]
    public void FailedRetentionLeavesEveryCategoryAndTheSourceUnchanged() {
        var source = SavedSession().Document["session"]!.AsObject(); var space = source["spaces"]![0]!;
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneDay", ["archive"] = "oneDay" };
        space["history"] = new JsonArray(new JsonObject {
            ["id"] = Guid.NewGuid().ToString(),
            ["url"] = "https://example.com/old",
            ["title"] = "Old visit",
            ["firstVisitedAt"] = 0.0,
            ["lastVisitedAt"] = 0.0,
            ["visitCount"] = 1
        });
        space["archivedTabs"] = new JsonArray(new JsonObject { ["tab"] = space["tabs"]![0]!.DeepClone(), ["archivedAt"] = "invalid" });
        var before = Bytes(source);
        Assert.Equal(BrowserRuleCodes.InvalidSavedState,
            Assert.Throws<BrowserRuleException>(() => NativeSessionMaintenance.Retain(source, 800000000)).Code);
        Assert.Equal(before, Bytes(source));
        space["archivedTabs"] = new JsonArray();
        var retained = NativeSessionMaintenance.Retain(source, 800000000);
        Assert.True(retained["changed"]!.GetValue<bool>());
        Assert.Empty(retained["session"]!["spaces"]![0]!["history"]!.AsArray());
        Assert.Single(space["history"]!.AsArray());
    }

    [Fact]
    public void PreparedSyncFailureCannotAdvanceTheJournalAfterLocalStaging() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial)); var before = journal.Read().ToArray();
        var space = NativeSyncProjection.Project(session, SyncProjectionPreferences(), [])
            .Single(n => n!["type"]!.GetValue<string>() == "space")!;
        space["value"]!["profileID"] = Guid.NewGuid().ToString("D");
        var incoming = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = "space", ["value"] = fixture.Space.ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space),
            ["payload"] = space.DeepClone(),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") }
        };
        var request = new JsonObject {
            ["version"] = 1,
            ["operation"] = "merge",
            ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(),
            ["records"] = new JsonArray(incoming),
            ["now"] = 800000000.0
        };
        var error = Assert.Throws<NativeSyncDocumentException>(() => NativeSyncSessionTransition.Prepare(journal, Bytes(request)));
        Assert.Equal("immutableProfileChanged", error.Code);
        Assert.Equal(before, journal.Read());
    }

    [Fact]
    public void ReplacingASeedWithCloudProducesAMatchedNonDisposableSessionAndJournal() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial));
        var staged = journal.Apply(JournalCommand(initial, "stage", new JsonObject { ["session"] = session.DeepClone(), ["deletionReason"] = "superseded", ["now"] = 800000000.0 }));
        var records = JsonNode.Parse(staged.Read())!["records"]!.DeepClone();
        session["disposableSeedMarker"] = Guid.NewGuid().ToString("D");
        var transition = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "replace",
            ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(),
            ["records"] = records,
            ["now"] = 800000000.0
        }));
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
    public void CloudReplacementCannotDiscardLocallyAuthorizedCleanup() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["spaceDeletions"] = new JsonArray(new JsonObject {
            ["spaceID"] = session["spaces"]![0]!["id"]!.DeepClone(),
            ["profileID"] = session["spaces"]![0]!["profile"]!["id"]!.DeepClone(),
            ["operationID"] = Guid.NewGuid().ToString("D").ToUpperInvariant()
        });
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial));
        var transition = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "replace",
            ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(),
            ["records"] = new JsonArray(),
            ["now"] = 800000000.0
        }));
        var result = transition.Materialization["session"]!;
        Assert.True(JsonNode.DeepEquals(session["spaceDeletions"], result["spaceDeletions"]));
        Assert.Equal(2, result["spaces"]!.AsArray().Count);
        var kept = result["spaces"]!.AsArray().Single(s => JsonNode.DeepEquals(s!["id"], session["spaces"]![0]!["id"]));
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0], kept));
        Assert.False(JsonNode.DeepEquals(result["selectedSpaceID"], kept!["id"]));
        var repaired = NativeSessionMaintenance.Repair(result.AsObject(), 800000000.0)["session"]!;
        Assert.True(JsonNode.DeepEquals(result["spaceDeletions"], repaired["spaceDeletions"]));
        var tombstone = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = "space", ["value"] = fixture.Space.ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") },
            ["tombstone"] = new JsonObject { ["reason"] = "explicitDelete", ["deletedAt"] = 800000000.0 }
        };
        var merged = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "merge",
            ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(),
            ["records"] = new JsonArray(tombstone),
            ["now"] = 800000000.0
        }));
        var record = JsonNode.Parse(merged.Journal.Read())!["records"]!.AsArray().Single(r =>
            r!["id"]!["kind"]!.GetValue<string>() == "space" && Guid.Parse(r["id"]!["value"]!.GetValue<string>()) == fixture.Space)!;
        Assert.Equal("explicitDelete", record["tombstone"]!["reason"]!.GetValue<string>());
        Assert.Single(merged.Materialization["session"]!["spaceDeletions"]!.AsArray());
    }
    [Theory]
    [InlineData("merge", "space", "explicitDelete", true)]
    [InlineData("replace", "space", "explicitDelete", true)]
    [InlineData("merge", "space", "retention", false)]
    [InlineData("replace", "space", "superseded", false)]
    [InlineData("merge", "tab", "explicitDelete", false)]
    [InlineData("replace", "absent", "explicitDelete", false)]
    public void OnlyAcceptedExplicitSpaceDeletionAuthorizesLocalCleanup(string operation, string kind, string reason, bool expected) {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var before = Bytes(session);
        var journal = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()))));
        var incoming = new JsonArray();
        if (kind != "absent") incoming.Add((JsonNode)new JsonObject {
            ["id"] = new JsonObject { ["kind"] = kind, ["value"] = (kind == "space" ? fixture.Space : fixture.Tab).ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") },
            ["tombstone"] = new JsonObject { ["reason"] = reason, ["deletedAt"] = 800000000.0 }
        });
        var transition = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = operation,
            ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(),
            ["records"] = incoming,
            ["now"] = 800000000.0
        }));
        Assert.Equal(before, Bytes(session));
        var result = transition.Materialization["session"]!;
        Assert.Equal(expected, result["spaceDeletions"] is JsonArray { Count: 1 });
        if (!expected) return;
        var intent = result["spaceDeletions"]![0]!;
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0]!["profile"]!["id"], intent["profileID"]));
        Assert.Equal(2, result["spaces"]!.AsArray().Count); // Keep one usable Space when the last remote Space is deleted.
        var frozen = result["spaces"]!.AsArray().Single(s => JsonNode.DeepEquals(s!["id"], intent["spaceID"]));
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0], frozen));
        Assert.False(JsonNode.DeepEquals(result["selectedSpaceID"], intent["spaceID"]));
        var tombstone = JsonNode.Parse(transition.Journal.Read())!["records"]!.AsArray().Single(r =>
            r!["id"]!["kind"]!.GetValue<string>() == "space" && Guid.Parse(r["id"]!["value"]!.GetValue<string>()) == fixture.Space)!;
        Assert.Equal("explicitDelete", tombstone["tombstone"]!["reason"]!.GetValue<string>());
    }

    [Fact]
    public void RemoteCleanupRequiresTheSealedOwningSyncTransactionAndPublishesAtomically() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session));
        var sync = new NativeSyncAuthority(new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid())))));
        owner.AttachSync(sync);
        using var transaction = sync.Prepare(Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "merge",
            ["session"] = session.DeepClone(),
            ["now"] = 800000000.0,
            ["records"] = new JsonArray(new JsonObject {
                ["id"] = new JsonObject { ["kind"] = "space", ["value"] = fixture.Space.ToString("D") },
                ["spaceID"] = SwiftId(fixture.Space),
                ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") },
                ["tombstone"] = new JsonObject { ["reason"] = "explicitDelete", ["deletedAt"] = 800000000.0 }
            })
        }));
        var result = JsonNode.Parse(transaction.Materialization!)!["value"]!["session"]!;
        byte[] Delta(JsonNode value) {
            string[] sections = ["tabs", "folders", "archivedTabs", "history"];
            var metadata = value.DeepClone().AsObject(); metadata.Remove("spaces");
            var spaces = new JsonArray();
            foreach (var space in value["spaces"]!.AsArray()) {
                var fields = space!.DeepClone().AsObject();
                var change = new JsonObject { ["id"] = space["id"]!.DeepClone() };
                foreach (var section in sections) { fields.Remove(section); change[section] = new JsonObject { ["replace"] = space[section]?.DeepClone() ?? new JsonArray() }; }
                change["metadata"] = fields; spaces.Add((JsonNode)change);
            }
            return Bytes(new JsonObject {
                ["version"] = 1,
                ["metadata"] = metadata,
                ["spaces"] = spaces,
                ["spaceOrder"] = new JsonArray(value["spaces"]!.AsArray().Select(s => s!["id"]!.DeepClone()).ToArray())
            });
        }
        Assert.Throws<BrowserRuleException>(() => owner.ReserveReplacement(Delta(result), transaction));
        Assert.True(transaction.Seal());
        Assert.Throws<BrowserRuleException>(() => owner.Commit(Delta(result)));
        var foreign = new NativeSessionAuthority(Bytes(session));
        Assert.Throws<BrowserRuleException>(() => foreign.ReserveReplacement(Delta(result), transaction));
        var altered = result.DeepClone(); altered["spaceDeletions"]![0]!["operationID"] = Guid.NewGuid().ToString("D");
        Assert.Throws<BrowserRuleException>(() => owner.ReserveReplacement(Delta(altered), transaction));
        result["spaceDeletions"]![0]!["operationID"] = result["spaceDeletions"]![0]!["operationID"]!.GetValue<string>().ToUpperInvariant();
        var before = sync.Snapshot.Read();
        using (owner.ReserveReplacement(Delta(result), transaction)) { }
        Assert.Equal(1UL, owner.Revision);
        Assert.Equal(before, sync.Snapshot.Read());
        using var accepted = owner.ReserveReplacement(Delta(result), transaction);
        Assert.Single(JsonNode.Parse(accepted.Checkpoint.Read("core"))!["spaceDeletions"]!.AsArray());
        accepted.Commit();
        Assert.Equal(transaction.Journal.Read(), sync.Snapshot.Read());
        Assert.Throws<BrowserRuleException>(() => owner.ReserveReplacement(Delta(result), transaction));
    }

}
