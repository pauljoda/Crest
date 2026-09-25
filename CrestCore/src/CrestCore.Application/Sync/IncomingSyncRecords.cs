using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Records the cloud transport sent, read into the journal's form and checked
/// before any of them reaches the journal or the session. A record the core
/// cannot take refuses the whole batch with `InvalidSyncRecords`: every failure
/// to read one is its flaw, never a fault of the core's.
internal sealed class IncomingSyncRecords {
    #region Static Variables

    /// How deep a record's body may nest, as the journal reads it.
    private static readonly JsonDocumentOptions BodyDocument = new() { MaxDepth = 64 };

    #endregion

    #region Variables

    /// Each record as the journal holds it, in the order they arrived.
    private readonly IReadOnlyList<JsonObject> nodes;

    /// Each record's Space, by its name in the journal.
    private readonly IReadOnlyDictionary<string, Guid> spaces;

    #endregion

    #region Constructors

    /// Reads `records`. Throws `Rejected` with `InvalidSyncRecords` for more
    /// records than a journal keeps, two that share an identity, and one that
    /// cannot be read or whose contents name another record.
    public IncomingSyncRecords(IReadOnlyList<SyncRecord> records) {
        if (records.Count > NativeSyncJournal.MaximumRecords) throw Refused(SyncRecordFlaw.TooManyRecords, subject: null);
        var read = new List<JsonObject>(records.Count);
        var names = new Dictionary<string, Guid>(StringComparer.Ordinal);
        foreach (var record in records) {
            var node = Node(record);
            if (!names.TryAdd(Name(record), record.SpaceId)) throw Refused(SyncRecordFlaw.DuplicateRecord, record.Id);
            read.Add(node);
        }
        nodes = read;
        spaces = names;
    }

    #endregion

    #region Actions - Reading

    /// The records as a journal request carries them, each a copy.
    public JsonArray Batch() => new([.. nodes.Select(node => (JsonNode?)node.DeepClone())]);

    /// Throws `Rejected` with `InvalidSyncRecords` naming `ChangedSpace` for a
    /// record `journal` holds in another Space than the one it arrived in.
    public void RequireSameSpaces(NativeSyncJournal journal) {
        foreach (var (name, space) in spaces)
            if (journal.SpaceOf(name) is { } held && held != space) throw Refused(SyncRecordFlaw.ChangedSpace, spaceOfName: name);
    }

    /// `record` as the journal holds it, in the member order and spelling the
    /// Apple clients write: its identity, its Space, its version, then its
    /// payload or its tombstone.
    private static JsonObject Node(SyncRecord record) {
        if (record.Id == Guid.Empty || record.SpaceId == Guid.Empty || record.Version.DeviceId == Guid.Empty)
            throw Refused(SyncRecordFlaw.MalformedRecord, record.Id);
        if (record.Kind.NamesItsSpace && record.Id != record.SpaceId) throw Refused(SyncRecordFlaw.IdentityMismatch, record.Id);
        JsonObject body;
        try {
            body = JsonNode.Parse(record.Body, documentOptions: BodyDocument) as JsonObject
                ?? throw Refused(SyncRecordFlaw.MalformedRecord, record.Id);
        } catch (JsonException) {
            throw Refused(SyncRecordFlaw.MalformedRecord, record.Id);
        }
        var node = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = record.Kind.Name, ["value"] = Spelled(record.Id) },
            ["spaceID"] = new JsonObject { ["rawValue"] = Spelled(record.SpaceId) },
            ["version"] = new JsonObject { ["logicalClock"] = record.Version.Clock, ["deviceID"] = Spelled(record.Version.DeviceId) },
            [record.IsTombstone ? "tombstone" : "payload"] = body
        };
        // Every rule the journal reads a record by, applied before it does.
        try {
            NativeSyncEvaluator.ValidateRecord(node);
        } catch (BrowserRuleException error) when (error.Code == BrowserRuleCodes.SyncIdentityMismatch) {
            throw Refused(SyncRecordFlaw.IdentityMismatch, record.Id);
        } catch (Exception error) when (error is not Rejected) {
            throw Refused(SyncRecordFlaw.MalformedRecord, record.Id);
        }
        return node;
    }

    /// A record's name in the journal.
    private static string Name(SyncRecord record) => record.Kind.Name + ":" + record.Id.ToString("D");

    /// An identity as the Apple clients spell it.
    private static string Spelled(Guid id) => id.ToString("D").ToUpperInvariant();

    private static Rejected Refused(SyncRecordFlaw flaw, Guid? subject) => new(new InvalidSyncRecords(flaw, subject));

    private static Rejected Refused(SyncRecordFlaw flaw, string spaceOfName) =>
        Refused(flaw, Guid.Parse(spaceOfName[(spaceOfName.IndexOf(':') + 1)..]));

    #endregion
}
