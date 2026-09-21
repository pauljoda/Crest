namespace CrestCore.Application;

/// Stable accent identifiers in native session metadata.
internal static class SpaceAccentCodes {
    #region Variables

    internal const string Indigo = "indigo";
    internal const string Orange = "orange";
    internal const string Teal = "teal";
    internal const string Rose = "rose";

    #endregion

    #region Actions - Validation

    internal static bool Includes(string? accent)
        => accent is Indigo or Orange or Teal or Rose;

    #endregion
}
