namespace CrestCore.Contracts;

/// A kind of record sync carries: its name, which a record's identity and the
/// journal spell, the CloudKit record type it travels as, and whether a record
/// of the kind is its Space.
///
/// A kind travels as its index in `All`, so `All` is append-only.
public sealed class SyncRecordKind {
    #region Static Variables

    public static readonly SyncRecordKind Space = new(name: "space", cloudRecordType: "CrestSpace", namesItsSpace: true);
    public static readonly SyncRecordKind Folder = new(name: "folder", cloudRecordType: "CrestFolder", namesItsSpace: false);
    public static readonly SyncRecordKind Tab = new(name: "tab", cloudRecordType: "CrestTab", namesItsSpace: false);
    public static readonly SyncRecordKind History = new(name: "history", cloudRecordType: "CrestHistory", namesItsSpace: false);
    public static readonly SyncRecordKind Archive = new(name: "archive", cloudRecordType: "CrestArchive", namesItsSpace: false);

    public static IReadOnlyList<SyncRecordKind> All { get; } = [Space, Folder, Tab, History, Archive];

    #endregion

    #region Variables

    /// How a record's identity and the journal spell the kind.
    public string Name { get; }

    /// The CloudKit record type a record of the kind travels as.
    public string CloudRecordType { get; }

    /// A record of the kind is its Space, so its identity is its Space's.
    public bool NamesItsSpace { get; }

    #endregion

    #region Constructors

    private SyncRecordKind(string name, string cloudRecordType, bool namesItsSpace) {
        Name = name;
        CloudRecordType = cloudRecordType;
        NamesItsSpace = namesItsSpace;
    }

    #endregion

    #region Actions - Lookup

    public static SyncRecordKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
