namespace CrestCore.Contracts;

/// The tab shows the Start Page and is its Space's only tab, so closing it
/// leaves nothing but its window to close.
public sealed record LastStartPage(Guid TabId) : Rejection;
