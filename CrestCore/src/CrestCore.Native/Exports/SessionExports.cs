using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

/// TRANSITIONAL until slice 8a (typed sync): what the durable JSON
/// replacement reads, which names the workspace it acts on by the identity the
/// core published for it.
public static unsafe partial class Exports {
    #region Actions - Validation

    private static bool ValidSessionInput(byte* bytes, nuint count) => bytes != null && count is > 0 and <= NativeSessionAuthority.MaximumBytes;

    /// A command prepared against a state the session has since replaced
    /// answers INVALID_STATE; any other refusal is INVALID_MESSAGE.
    private static int SessionError(Exception error) => error is Rejected { Rejection: StaleCommand }
        ? CoreStatus.InvalidState : CoreStatus.InvalidMessage;

    /// The workspace identity at `workspace`: 16 RFC 4122 bytes.
    private static Guid Workspace(byte* workspace) => new(new ReadOnlySpan<byte>(workspace, 16), bigEndian: true);

    #endregion
}
