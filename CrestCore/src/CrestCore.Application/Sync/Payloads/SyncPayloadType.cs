using CrestCore.Contracts;

namespace CrestCore.Application;

/// A kind of payload the journal and the cloud carry, with how its value is
/// read. A payload names its type by its kind's name.
internal sealed class SyncPayloadType {
    #region Static Variables

    public static readonly SyncPayloadType Space = new(SyncRecordKind.Space, SpacePayload.Read);
    public static readonly SyncPayloadType Folder = new(SyncRecordKind.Folder, FolderPayload.Read);
    public static readonly SyncPayloadType Tab = new(SyncRecordKind.Tab, TabPayload.Read);
    public static readonly SyncPayloadType History = new(SyncRecordKind.History, HistoryPayload.Read);
    public static readonly SyncPayloadType Archive = new(SyncRecordKind.Archive, ArchivePayload.Read);

    public static IReadOnlyList<SyncPayloadType> All { get; } = [Space, Folder, Tab, History, Archive];

    #endregion

    #region Variables

    /// The kind of record a payload of this type is.
    public SyncRecordKind Kind { get; }

    /// Reads a payload's value.
    private readonly Func<SyncPayloadReader, SyncPayload> read;

    #endregion

    #region Constructors

    private SyncPayloadType(SyncRecordKind kind, Func<SyncPayloadReader, SyncPayload> read) {
        Kind = kind;
        this.read = read;
    }

    #endregion

    #region Actions - Reading

    /// The type a payload spells `name`, or null when no client knows one.
    public static SyncPayloadType? Named(string? name) => All.FirstOrDefault(type => type.Kind.Name == name);

    /// The payload `value` holds. Throws `UnreadableSyncPayloadException` for
    /// one no client reads.
    public SyncPayload Read(SyncPayloadReader value) => read(value);

    #endregion
}
