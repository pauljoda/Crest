namespace CrestCore.Contracts;

/// Why the session's storage could not be read or written.
public enum StorageFailure {
    /// The disk has no room for the write.
    DiskFull,
    /// The file or its directory cannot be written.
    ReadOnly,
    /// Another connection held the file for longer than the core waits.
    Busy,
    /// The file is not a readable session: a damaged database, a missing part
    /// or a part that does not decode.
    Damaged,
    /// Any other failure to open, read or write the file.
    Unavailable
}
