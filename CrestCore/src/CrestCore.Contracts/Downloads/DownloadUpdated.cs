namespace CrestCore.Contracts;

/// A download record changed or began. `Position` is its place in the
/// newest-first list after the change.
public sealed record DownloadUpdated(DownloadState Download, int Position) : Change;
