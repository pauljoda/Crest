using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed class NativeSessionCommand {
    #region Variables

    private readonly NativeSessionAuthority owner;
    internal ulong ExpectedRevision { get; }
    internal SessionState Session { get; }
    public byte[] Output { get; }
    private readonly string? rejection;
    internal ulong? BorrowedSourceRevision { get; }
    internal Guid? TransientCompletion { get; }

    #endregion

    #region Constructors

    internal NativeSessionCommand(NativeSessionAuthority owner, ulong revision,
        SessionState session, byte[] output, string? rejection = null, Guid? transientCompletion = null) {
        this.owner = owner; ExpectedRevision = revision; Session = session; Output = output; this.rejection = rejection;
        BorrowedSourceRevision = owner.BorrowedRevision;
        TransientCompletion = transientCompletion;
    }

    #endregion

    #region Actions - Commands

    internal void RequireAccepted() {
        if (rejection is not null) throw new BrowserRuleException(rejection);
        owner.RequireBorrowedRevision(BorrowedSourceRevision);
        owner.RequirePendingTransient(TransientCompletion);
    }

    public ulong Commit() => owner.CommitCommand(this);

    /// Commits with `durability`, saving `transaction`'s journal with the session.
    public ulong Commit(Durability durability, NativeSyncTransaction? transaction = null) =>
        owner.Commit(this, durability, transaction);

    internal NativeSessionReplacement Reserve() => owner.ReserveCommand(this);

    #endregion
}
