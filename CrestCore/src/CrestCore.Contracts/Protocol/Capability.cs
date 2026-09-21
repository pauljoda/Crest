namespace CrestCore.Contracts;

public sealed record Capability(string Status, int Version, string Scope, string[] Limitations, string Evidence);
