namespace CrestCore.Contracts;

public sealed record Capability(CapabilityStatus Status, int Version, string Scope, string[] Limitations, string Evidence);
