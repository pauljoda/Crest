namespace CrestCore.Contracts;

/// The receipt of a cloud intent that left records out: `Unreadable` records
/// no client of this build's schema reads, and `FromNewerBuild` records a
/// newer build wrote for a schema this build does not know. Nothing else about
/// the intent changes; the transport tells the person, and that updating Crest
/// on this device reads the second kind.
public sealed record SyncRecordsSkipped(int Unreadable, int FromNewerBuild) : Change;
