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
