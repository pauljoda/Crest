using CrestCore.Domain;

namespace CrestCore.Application;

internal static class NativeEditTimestamp {
    #region Variables

    private const double SwiftEpochOffset = 978307200;

    #endregion

    #region Actions - Session

    // Preserve Swift Date's Unix-to-reference-epoch floating-point conversion,
    // including its binary representation, so repair cannot invent a new edit.
    internal static double Normalize(double referenceSeconds) =>
        BrowserEditTimestamp.NormalizeUnixSeconds(referenceSeconds + SwiftEpochOffset) - SwiftEpochOffset;

    internal static double Encode(DateTimeOffset value) =>
        BrowserEditTimestamp.NormalizeUnixSeconds((value - DateTimeOffset.UnixEpoch).TotalSeconds) - SwiftEpochOffset;

    #endregion
}
