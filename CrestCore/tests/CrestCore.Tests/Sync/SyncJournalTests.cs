using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonObject JournalDocument(JsonObject record, ulong? clock = null) => new() {
        ["schemaVersion"] = 1,
        ["deviceID"] = Guid.NewGuid().ToString().ToUpperInvariant(),
        ["logicalClock"] = clock ?? 1UL,
        ["preferences"] = new JsonObject { ["savedStructure"] = true, ["currentTabs"] = true, ["historyAndArchive"] = true, ["extensionSettings"] = false },
        ["records"] = new JsonArray(record.DeepClone()),
        ["pendingRecordIDs"] = new JsonArray(record["id"]!.DeepClone())
    };
    private static byte[] JournalCommand(JsonObject document, string operation, JsonObject arguments) => Bytes(new JsonObject {
        ["version"] = 1,
        ["operation"] = operation,
        ["preferences"] = document["preferences"]!.DeepClone(),
        ["arguments"] = arguments
    });

    [Fact]
    public void UUIDLetterCaseDoesNotCreateEditsButCaseChangesInTitlesStillDo() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        var payload = record["payload"]!["value"]!;
        payload["title"] = "ABCDEFAB-1234-1234-1234-ABCDEFABCDEF";
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var desired = record["payload"]!.DeepClone();
        desired["value"]!["id"]!["rawValue"] = IdForTest(payload["id"]!).ToLowerInvariant();
        desired["value"]!["spaceID"]!["rawValue"] = IdForTest(payload["spaceID"]!).ToLowerInvariant();
        byte[] Stage() => JournalCommand(document, "stage", new() {
            ["payloads"] = new JsonArray(desired.DeepClone()),
            ["archiveReasons"] = new JsonArray(),
            ["deletionReason"] = "superseded",
            ["now"] = 100.0
        });
        var unchanged = journal.Apply(Stage());
        Assert.Equal(1UL, JsonNode.Parse(unchanged.Read())!["logicalClock"]!.GetValue<ulong>());
        desired["value"]!["title"] = payload["title"]!.GetValue<string>().ToLowerInvariant();
        Assert.Equal(2UL, JsonNode.Parse(unchanged.Apply(Stage()).Read())!["logicalClock"]!.GetValue<ulong>());
        static string IdForTest(JsonNode value) => value["rawValue"]!.GetValue<string>();
    }

    [Fact]
    public void TimestampEncodingDoesNotCreateEditsButDifferentDateValuesStillDo() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        record["payload"]!["value"]!["positionModifiedAt"] = JsonNode.Parse("811615335.98");
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var desired = record["payload"]!.DeepClone();
        desired["value"]!["positionModifiedAt"] = JsonNode.Parse("811615335.98000002");
        byte[] Stage() => JournalCommand(document, "stage", new() {
            ["payloads"] = new JsonArray(desired.DeepClone()),
            ["archiveReasons"] = new JsonArray(),
            ["deletionReason"] = "superseded",
            ["now"] = 100.0
        });
        var unchanged = journal.Apply(Stage());
        Assert.Equal(1UL, JsonNode.Parse(unchanged.Read())!["logicalClock"]!.GetValue<ulong>());
        desired["value"]!["positionModifiedAt"] = Math.BitIncrement(811615335.98);
        Assert.Equal(2UL, JsonNode.Parse(unchanged.Apply(Stage()).Read())!["logicalClock"]!.GetValue<ulong>());
    }

    [Fact]
    public void RestagingRetainsAdditiveFieldsWithoutRevivingClearedFieldsOrRemovedMembers() {
        var session = SavedSession().Document["session"]!.AsObject();
        var payload = NativeSyncProjection.Project(session, SyncProjectionPreferences(), [])[0]!.AsObject();
        var groupA = new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["customTitle"] = "Clear me", ["futureGroup"] = "a" };
        var groupB = new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["futureGroup"] = "b" };
        var removed = new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["futureGroup"] = "removed" };
        payload["futureEnvelope"] = new JsonArray(true, "opaque", null);
        payload["value"]!["futureSpace"] = ulong.MaxValue;
        payload["value"]!["branding"] = new JsonObject {
            ["futureBranding"] = "kept",
            ["symbolColor"] = new JsonObject { ["red"] = 1.0 },
            ["crest"] = new JsonObject { ["symbol"] = "lion", ["charge"] = new JsonObject { ["kind"] = "system", ["value"] = "star" }, ["futureCrest"] = 4 }
        };
        payload["value"]!["splitGroups"] = new JsonArray(groupA, groupB, removed);
        var record = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = "space", ["value"] = IdForTest(payload["value"]!["id"]!) },
            ["spaceID"] = payload["value"]!["id"]!.DeepClone(),
            ["payload"] = payload.DeepClone(),
            ["version"] = new JsonObject { ["logicalClock"] = 1UL, ["deviceID"] = Guid.NewGuid().ToString() },
            ["futureRecord"] = "kept"
        };
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var desired = payload.DeepClone().AsObject(); desired.Remove("futureEnvelope");
        var value = desired["value"]!.AsObject(); value.Remove("futureSpace"); value["name"] = "Renamed";
        value["branding"] = new JsonObject { ["crest"] = new JsonObject { ["symbol"] = "oak" } };
        value["splitGroups"] = new JsonArray(new JsonObject { ["id"] = groupB["id"]!.DeepClone() }, new JsonObject { ["id"] = groupA["id"]!.DeepClone() });
        var command = JournalCommand(document, "stage", new() {
            ["payloads"] = new JsonArray(desired),
            ["archiveReasons"] = new JsonArray(),
            ["deletionReason"] = "explicitDelete",
            ["now"] = 100.0
        });
        var updated = new NativeSyncJournal(journal.Apply(command).Read());
        var result = JsonNode.Parse(updated.Read())!["records"]![0]!;
        Assert.Equal("kept", result["futureRecord"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(payload["futureEnvelope"], result["payload"]!["futureEnvelope"]));
        var body = result["payload"]!["value"]!;
        Assert.Equal(ulong.MaxValue, body["futureSpace"]!.GetValue<ulong>());
        Assert.Equal("Renamed", body["name"]!.GetValue<string>());
        Assert.Equal("kept", body["branding"]!["futureBranding"]!.GetValue<string>());
        Assert.Equal(4, body["branding"]!["crest"]!["futureCrest"]!.GetValue<int>());
        Assert.Null(body["branding"]!["symbolColor"]); Assert.Null(body["branding"]!["crest"]!["charge"]);
        Assert.Equal(new[] { "b", "a" }, body["splitGroups"]!.AsArray().Select(g => g!["futureGroup"]!.GetValue<string>()));
        Assert.Null(body["splitGroups"]![1]!["customTitle"]);
        Assert.Equal(2UL, JsonNode.Parse(updated.Apply(command).Read())!["logicalClock"]!.GetValue<ulong>());
        var deleted = updated.Apply(JournalCommand(document, "stage", new() {
            ["payloads"] = new JsonArray(),
            ["archiveReasons"] = new JsonArray(),
            ["deletionReason"] = "explicitDelete",
            ["now"] = 101.0
        }));
        Assert.Null(JsonNode.Parse(deleted.Read())!["records"]![0]!["payload"]);
        Assert.Equal("explicitDelete", JsonNode.Parse(deleted.Read())!["records"]![0]!["tombstone"]!["reason"]!.GetValue<string>());
        static string IdForTest(JsonNode value) => value["rawValue"]!.GetValue<string>();
    }

    [Fact]
    public void AdditiveTabFieldsFollowArchiveAndRestore() {
        var tab = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        tab["payload"]!["value"]!["futureTab"] = "retained";
        var document = JournalDocument(tab);
        var journal = new NativeSyncJournal(Bytes(document));
        var knownTab = tab["payload"]!["value"]!.DeepClone().AsObject(); knownTab.Remove("futureTab");
        var archive = new JsonObject {
            ["type"] = "archive",
            ["value"] = new JsonObject {
                ["tab"] = knownTab.DeepClone(),
                ["archivedAt"] = 200.0,
                ["reason"] = "closed"
            }
        };
        byte[] Stage(JsonObject payload) => JournalCommand(document, "stage", new() {
            ["payloads"] = new JsonArray(payload.DeepClone()),
            ["archiveReasons"] = new JsonArray(),
            ["deletionReason"] = "superseded",
            ["now"] = 200.0
        });
        var archived = journal.Apply(Stage(archive));
        var records = JsonNode.Parse(archived.Read())!["records"]!.AsArray();
        var archivedRecord = records.Single(r => r!["id"]!["kind"]!.GetValue<string>() == "archive")!;
        Assert.Equal("retained", archivedRecord["payload"]!["value"]!["tab"]!["futureTab"]!.GetValue<string>());
        // Restore on another client that received only the archive record.
        var restored = new NativeSyncJournal(Bytes(JournalDocument(archivedRecord.AsObject())))
            .Apply(Stage(new JsonObject { ["type"] = "tab", ["value"] = knownTab }));
        var restoredTab = JsonNode.Parse(restored.Read())!["records"]!.AsArray().Single(r => r!["id"]!["kind"]!.GetValue<string>() == "tab")!;
        Assert.Equal("retained", restoredTab["payload"]!["value"]!["futureTab"]!.GetValue<string>());
    }

    [Fact]
    public void SessionAndSyncPublishTogetherAndCannotAttachToAnotherOrPrivateWorkspace() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var record = SyncTabRecord(fixture.Tab, fixture.Space, 9, Guid.NewGuid());
        var document = JournalDocument(record);
        var initial = new NativeSyncJournal(Bytes(document));
        var sync = new NativeSyncAuthority(initial);
        var owner = new NativeSessionAuthority(Bytes(session));
        owner.AttachSync(sync);
        owner.AttachSync(sync); // A second window shares this family.
        Assert.Throws<BrowserRuleException>(() => new NativeSessionAuthority(Bytes(session)).AttachSync(sync));
        var privateSession = session.DeepClone().AsObject(); privateSession["coreWorkspaceKind"] = "private";
        Assert.Throws<BrowserRuleException>(() => new NativeSessionAuthority(Bytes(privateSession)).AttachSync(new(initial)));
        sync.Flush();
        var launched = sync.Snapshot;
        var request = JournalCommand(document, "acknowledge", new() { ["acknowledgements"] = new JsonArray(new JsonObject { ["id"] = record["id"]!.DeepClone() }) });
        using var transaction = sync.Prepare(request);
        Assert.True(transaction.Seal());
        using var replacement = owner.ReserveReplacement(RenameDelta(session, "Durable synced tab"));
        replacement.BindSync(transaction);
        Assert.Same(launched, sync.Snapshot);
        Assert.Equal(1UL, owner.Revision);
        replacement.Commit();
        Assert.Equal(2UL, owner.Revision);
        Assert.Same(transaction.Journal, sync.Snapshot);
        transaction.Commit(); // Native projection publishes after paired commit.
    }

    [Fact]
    public void JournalTransitionFailureKeepsOriginalClockPendingIDsAndRecords() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        var document = JournalDocument(record, ulong.MaxValue - 1);
        var journal = new NativeSyncJournal(Bytes(document));
        var before = journal.Read().ToArray();
        var changed = record["payload"]!.DeepClone(); changed["value"]!["title"] = "New title";
        var added = changed.DeepClone(); added["value"]!["id"] = SwiftId(Guid.NewGuid());
        var command = JournalCommand(document, "stage", new() {
            ["payloads"] = new JsonArray(changed, added),
            ["archiveReasons"] = new JsonArray(),
            ["deletionReason"] = "superseded",
            ["now"] = 100.0
        });
        Assert.Equal("sync_clock_exhausted", Assert.Throws<BrowserRuleException>(() => journal.Apply(command)).Code);
        Assert.Equal(before, journal.Read());
    }

    [Fact]
    public void JournalAcknowledgesOnlyExactVersionsAndSnapshotsRemainIndependent() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 9, Guid.NewGuid());
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var version = record["version"]!.DeepClone(); version["logicalClock"] = 8UL;
        byte[] Acknowledge(JsonNode version) => JournalCommand(document, "acknowledge", new() { ["acknowledgements"] = new JsonArray(new JsonObject { ["id"] = record["id"]!.DeepClone(), ["version"] = version.DeepClone() }) });
        var stale = journal.Apply(Acknowledge(version));
        Assert.Single(JsonNode.Parse(stale.Read())!["pendingRecordIDs"]!.AsArray());
        var accepted = stale.Apply(Acknowledge(record["version"]!));
        Assert.Empty(JsonNode.Parse(accepted.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.Single(JsonNode.Parse(journal.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.Equal(9UL, JsonNode.Parse(accepted.Read())!["logicalClock"]!.GetValue<ulong>());
    }
}
