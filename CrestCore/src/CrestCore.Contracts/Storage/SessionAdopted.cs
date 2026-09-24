namespace CrestCore.Contracts;

/// The session file holds its first session. `Favicons` are the images the
/// adopted session carried inside its tabs, for the host's image store; the
/// core keeps none of them.
public sealed record SessionAdopted(IReadOnlyList<TabFavicon> Favicons) : Change;
