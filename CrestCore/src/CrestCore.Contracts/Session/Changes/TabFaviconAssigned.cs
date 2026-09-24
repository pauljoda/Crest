namespace CrestCore.Contracts;

/// <summary>The core decided which image a tab shows. When <see cref="Adopts"/> it
/// wears the image <see cref="PageId"/> reported, or with no page the one the
/// issuer of its command offered; otherwise it wears none. The image bytes stay
/// with the platform.</summary>
public sealed record TabFaviconAssigned(Guid WorkspaceId, Guid TabId, bool Adopts, Guid? PageId) : Change;
