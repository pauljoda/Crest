namespace CrestCore.Contracts;

/// <summary>A command decided which image a tab shows: the one the page that issued
/// the command reported when <see cref="Adopts"/>, else none. The image bytes stay
/// with the platform.</summary>
public sealed record TabFaviconAssigned(Guid WorkspaceId, Guid TabId, bool Adopts) : Change;
