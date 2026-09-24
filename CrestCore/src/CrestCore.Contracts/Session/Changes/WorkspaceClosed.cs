namespace CrestCore.Contracts;

/// <summary>A workspace left this device, and its windows with it.</summary>
public sealed record WorkspaceClosed(Guid WorkspaceId) : Change;
