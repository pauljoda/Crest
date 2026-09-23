namespace CrestCore.Contracts;

/// A download's text field is empty or longer than its limit.
public sealed record InvalidDownloadText(DownloadTextField Field) : Rejection;
