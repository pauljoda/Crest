namespace CrestCore.Contracts;

/// A registered adapter's descriptor. Capabilities stay keyed by the names the
/// descriptor spelled, including ones this build does not know.
public sealed record Adapter(string Id, AdapterRole Role, string Implementation, string Version,
    IReadOnlyDictionary<string, Capability> Capabilities) {
    #region Actions - Protocol

    public bool Supports(EngineCapability capability) {
        ArgumentNullException.ThrowIfNull(capability);
        return Capabilities.TryGetValue(capability.Name, out var declared) && declared.Status.IsAvailable
            && declared.Version == 1;
    }

    #endregion
}
