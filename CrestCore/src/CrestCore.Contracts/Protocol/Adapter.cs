namespace CrestCore.Contracts;

public sealed record Adapter(string Id, string Role, string Implementation, string Version,
    IReadOnlyDictionary<string, Capability> Capabilities) {
    #region Actions - Protocol

    public bool Supports(string name) => Capabilities.TryGetValue(name, out var c)
        && c.Status == CapabilityStatuses.Supported && c.Version == 1;

    #endregion
}
