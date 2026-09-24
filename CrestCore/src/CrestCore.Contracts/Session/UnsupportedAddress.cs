namespace CrestCore.Contracts;

/// `Url` is not an absolute address a page can load.
public sealed record UnsupportedAddress(string Url) : Rejection;
