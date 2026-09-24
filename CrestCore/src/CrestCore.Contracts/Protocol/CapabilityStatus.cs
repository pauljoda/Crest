namespace CrestCore.Contracts;

/// How far an adapter vouches for one capability it declares. Descriptors
/// spell a status as its `Name`.
public sealed class CapabilityStatus {
    #region Variables

    public static readonly CapabilityStatus Supported = new(name: "supported", isAvailable: true);
    public static readonly CapabilityStatus Partial = new(name: "partial");
    public static readonly CapabilityStatus Unavailable = new(name: "unavailable");
    public static readonly CapabilityStatus Unverified = new(name: "unverified");

    public static IReadOnlyList<CapabilityStatus> All { get; } = [Supported, Partial, Unavailable, Unverified];

    public string Name { get; }

    /// The core and shared UI may rely on a capability declared with this status.
    public bool IsAvailable { get; }

    #endregion

    #region Constructors

    private CapabilityStatus(string name, bool isAvailable = false) {
        Name = name;
        IsAvailable = isAvailable;
    }

    #endregion

    #region Actions - Lookup

    public static CapabilityStatus? Named(string? name) => All.FirstOrDefault(status => status.Name == name);

    #endregion
}
