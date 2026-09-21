namespace CrestCore.Contracts;

/// Stable support levels in adapter descriptors.
public static class CapabilityStatuses {
    #region Variables

    public const string Supported = "supported";
    public const string Partial = "partial";
    public const string Unavailable = "unavailable";
    public const string Unverified = "unverified";

    #endregion

    #region Actions - Validation

    public static bool Includes(string? status)
        => status is Supported or Partial or Unavailable or Unverified;

    #endregion
}
