namespace CrestCore.Contracts;

/// <summary>The session accepted another change after this command was prepared,
/// so the command no longer describes what it would change. Prepare it again.</summary>
public sealed record StaleCommand : Rejection;
