namespace CrestCore.Contracts;

/// The most bytes one encoded intent or query of the marked type may take.
/// Messages are small, so a type without the attribute takes at most
/// `DefaultBytes`; anything larger is a caller bug the core refuses before
/// reading it. The generator writes each limit into the codec the dispatcher
/// reads, and into the schema fingerprint.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class MessageLimitAttribute(int bytes) : Attribute {
    #region Static Variables

    /// The limit of every intent and query that names none.
    public const int DefaultBytes = 16 * 1024 * 1024;

    /// The limit of a message that carries a whole session or its records,
    /// which is as large as a stored session or sync journal may grow.
    public const int SessionBytes = 64 * 1024 * 1024;

    /// The limit of a message that also carries a legacy sync state beside a
    /// session's worth of records.
    public const int LegacySyncBytes = 2 * SessionBytes;

    #endregion

    #region Variables

    public int Bytes { get; } = bytes;

    #endregion
}
