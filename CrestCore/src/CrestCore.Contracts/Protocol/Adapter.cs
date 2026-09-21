namespace CrestCore.Contracts;

public sealed record Adapter(string Id, string Role, string Implementation, string Version,
    IReadOnlyDictionary<string, Capability> Capabilities) {
    public bool Supports(string name) => Capabilities.TryGetValue(name, out var c)
        && c.Status == "supported" && c.Version == 1;
}
