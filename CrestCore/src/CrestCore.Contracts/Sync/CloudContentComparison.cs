namespace CrestCore.Contracts;

/// Whether this device's journal and the cloud hold the same content: the same
/// records, each in the same Space with an equivalent payload or tombstone.
/// Versions do not count, and of two cloud records with one identity the later
/// counts. `DeviceRecords` and `CloudRecords` count every record each holds,
/// tombstones included; `DeviceSpaces` and `CloudSpaces` count the Spaces each
/// keeps. A device whose session is the disposable seed a first launch made
/// holds nothing.
public sealed record CloudContentComparison(bool Matches, int DeviceRecords, int CloudRecords, int DeviceSpaces, int CloudSpaces);
