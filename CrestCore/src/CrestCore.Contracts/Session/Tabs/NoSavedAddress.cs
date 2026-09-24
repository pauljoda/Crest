namespace CrestCore.Contracts;

/// The tab belongs to no address: it is an open tab, which goes wherever
/// browsing takes it, or a saved or pinned one that shows no web page.
public sealed record NoSavedAddress(Guid TabId) : Rejection;
