using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static JsonObject JournalDocument(JsonObject record, ulong? clock = null) => new()
    {
        ["schemaVersion"] = 1, ["deviceID"] = Guid.NewGuid().ToString().ToUpperInvariant(),
        ["logicalClock"] = clock ?? 1UL, ["preferences"] = new JsonObject
        { ["savedStructure"] = true, ["currentTabs"] = true, ["historyAndArchive"] = true, ["extensionSettings"] = false },
        ["records"] = new JsonArray(record.DeepClone()), ["pendingRecordIDs"] = new JsonArray(record["id"]!.DeepClone())
    };
    private static byte[] JournalCommand(JsonObject document, string operation, JsonObject arguments) => Bytes(new JsonObject
    {
        ["version"] = 1, ["operation"] = operation, ["preferences"] = document["preferences"]!.DeepClone(), ["arguments"] = arguments
    });

    [Fact]
    public void SyncOwnerRejectsSupersededPreparationsAndRetainsNewerRevisionDuringStorage()
    {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 9, Guid.NewGuid());
        var document = JournalDocument(record);
        var initial = new NativeSyncJournal(Bytes(document));
        var owner = new NativeSyncAuthority(initial);
        var request = JournalCommand(document, "acknowledge", new()
        { ["acknowledgements"] = new JsonArray(new JsonObject { ["id"] = record["id"]!.DeepClone() }) });
        using (var stale = owner.Prepare(1, request)!)
        {
            owner.Advance(2);
            Assert.Same(initial, owner.Snapshot);
            Assert.False(stale.Seal());
        }
        Assert.Null(owner.Prepare(1, request));
        using var saving = owner.Prepare(2, request)!;
        Assert.True(saving.Seal());
        owner.Advance(3); // Main-thread edit while the native worker saves.
        Assert.Same(initial, owner.Snapshot);
        saving.Commit();
        Assert.Empty(JsonNode.Parse(owner.Snapshot.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.Null(owner.Prepare(2, request));
        using var latest = owner.Prepare(3, request)!;
        Assert.True(latest.Seal());
    }

    [Fact]
    public void SessionAndSyncPublishTogetherAndCannotAttachToAnotherOrPrivateWorkspace()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var record = SyncTabRecord(fixture.Tab.Value, fixture.Space.Value, 9, Guid.NewGuid());
        var document = JournalDocument(record);
        var initial = new NativeSyncJournal(Bytes(document));
        var sync = new NativeSyncAuthority(initial);
        var owner = new NativeSessionAuthority(Bytes(session));
        owner.AttachSync(sync);
        owner.AttachSync(sync); // A second window shares this family.
        Assert.Throws<BrowserRuleException>(() => new NativeSessionAuthority(Bytes(session)).AttachSync(sync));
        var privateSession = session.DeepClone().AsObject(); privateSession["coreWorkspaceKind"] = "private";
        Assert.Throws<BrowserRuleException>(() => new NativeSessionAuthority(Bytes(privateSession)).AttachSync(new(initial)));
        var request = JournalCommand(document, "acknowledge", new()
        { ["acknowledgements"] = new JsonArray(new JsonObject { ["id"] = record["id"]!.DeepClone() }) });
        using var transaction = sync.Prepare(1, request)!;
        Assert.True(transaction.Seal());
        using var replacement = owner.ReserveReplacement(1, RenameDelta(session, "Durable synced tab"), Selection(session));
        replacement.BindSync(transaction);
        Assert.Same(initial, sync.Snapshot);
        Assert.Equal(1UL, owner.Revision);
        replacement.Commit();
        Assert.Equal(2UL, owner.Revision);
        Assert.Same(transaction.Journal, sync.Snapshot);
        transaction.Commit(); // Native projection publishes after paired commit.
    }

    [Fact]
    public void JournalTransitionFailureKeepsOriginalClockPendingIDsAndRecords()
    {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        var document = JournalDocument(record, ulong.MaxValue - 1);
        var journal = new NativeSyncJournal(Bytes(document));
        var before = journal.Read().ToArray();
        var changed = record["payload"]!.DeepClone(); changed["value"]!["title"] = "New title";
        var added = changed.DeepClone(); added["value"]!["id"] = SwiftId(Guid.NewGuid());
        var command = JournalCommand(document, "stage", new()
        {
            ["payloads"] = new JsonArray(changed, added), ["archiveReasons"] = new JsonArray(),
            ["deletionReason"] = "superseded", ["now"] = 100.0
        });
        Assert.Equal("sync_clock_exhausted", Assert.Throws<BrowserRuleException>(() => journal.Apply(command)).Code);
        Assert.Equal(before, journal.Read());
    }

    [Fact]
    public void JournalAcknowledgesOnlyExactVersionsAndSnapshotsRemainIndependent()
    {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 9, Guid.NewGuid());
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var version = record["version"]!.DeepClone(); version["logicalClock"] = 8UL;
        byte[] Acknowledge(JsonNode version) => JournalCommand(document, "acknowledge", new()
        { ["acknowledgements"] = new JsonArray(new JsonObject { ["id"] = record["id"]!.DeepClone(), ["version"] = version.DeepClone() }) });
        var stale = journal.Apply(Acknowledge(version));
        Assert.Single(JsonNode.Parse(stale.Read())!["pendingRecordIDs"]!.AsArray());
        var accepted = stale.Apply(Acknowledge(record["version"]!));
        Assert.Empty(JsonNode.Parse(accepted.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.Single(JsonNode.Parse(journal.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.Equal(9UL, JsonNode.Parse(accepted.Read())!["logicalClock"]!.GetValue<ulong>());
    }
}
