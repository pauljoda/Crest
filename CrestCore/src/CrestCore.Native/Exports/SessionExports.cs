using CrestCore.Application;

namespace CrestCore.Native;

/// TRANSITIONAL until slice 8a (typed sync): what the durable JSON
/// replacement reads, which names the workspace it acts on by the identity the
/// core published for it.
public static unsafe partial class Exports {
    #region Actions - Validation

    private static bool ValidSessionInput(byte* bytes, nuint count) => bytes != null && count is > 0 and <= NativeSessionAuthority.MaximumBytes;

    /// The workspace identity at `workspace`: 16 RFC 4122 bytes.
    private static Guid Workspace(byte* workspace) => new(new ReadOnlySpan<byte>(workspace, 16), bigEndian: true);

    #endregion
}
