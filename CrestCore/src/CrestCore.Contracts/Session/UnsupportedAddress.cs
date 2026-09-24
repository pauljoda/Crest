namespace CrestCore.Contracts;

/// `Url` names nothing a page can load: not an address a tab may show, nor
/// words to search for.
public sealed record UnsupportedAddress(string Url) : Rejection;
