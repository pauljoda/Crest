using CrestCore.Domain;

namespace CrestCore.Application;

public sealed class NativeSessionCommand {
    private readonly NativeSessionAuthority owner;
    internal ulong ExpectedRevision { get; }
    internal SessionDocument Document { get; }
    public byte[] Output { get; }
    private readonly string? rejection;
    internal ulong? BorrowedSourceRevision { get; }
    internal Guid? TransientCompletion { get; }
    internal void RequireAccepted() {
        if (rejection is not null) throw new BrowserRuleException(rejection);
        owner.RequireBorrowedRevision(BorrowedSourceRevision);
        owner.RequirePendingTransient(TransientCompletion);
    }
    internal NativeSessionCommand(NativeSessionAuthority owner, ulong revision,
        SessionDocument document, byte[] output, string? rejection = null, Guid? transientCompletion = null) {
        this.owner = owner; ExpectedRevision = revision; Document = document; Output = output; this.rejection = rejection;
        BorrowedSourceRevision = owner.BorrowedRevision;
        TransientCompletion = transientCompletion;
    }
    public ulong Commit() => owner.CommitCommand(this);
    public NativeSessionReplacement Reserve(ReadOnlySpan<byte> selection) => owner.ReserveCommand(this, selection);
}
