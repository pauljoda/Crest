namespace CrestCore.Contracts;

/// The image a tab shows, as the platform stored it.
public sealed record TabFavicon(Guid TabId, byte[] Image);
