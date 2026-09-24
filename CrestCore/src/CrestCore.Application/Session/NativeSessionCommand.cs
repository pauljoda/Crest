using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A prepared session command: the session it was prepared against, the one
/// it proposes and the answer its window reads. Committing it after the
/// session accepted anything else is refused with `StaleCommand`, so a command
/// never overwrites a change it did not see.
public sealed class NativeSessionCommand {
    #region Variables

    private readonly NativeSessionAuthority owner;
    /// The accepted session the command was prepared against.
    internal SessionState Base { get; }
    internal SessionState Session { get; }
    public byte[] Output { get; }
    private readonly string? rejection;
    internal Guid? TransientCompletion { get; }
    /// What the command chose for the window that issued it to show next.
    internal WindowFollowUp? FollowUp { get; }
    /// The tabs the command copied and the image it assigned, which the
    /// session's own changes cannot tell.
    internal SessionTabEvents Events { get; }
    /// How the command's edit reaches the sync journal, and so whether it is
    /// saved before the command returns; null for a command that stages
    /// nothing.
    internal SyncStaging? Staging { get; private set; }

    #endregion

    #region Constructors

    internal NativeSessionCommand(NativeSessionAuthority owner, SessionState basis,
        SessionState session, byte[] output, string? rejection = null, Guid? transientCompletion = null,
        WindowFollowUp? followUp = null, SessionTabEvents? events = null) {
        this.owner = owner; Base = basis; Session = session; Output = output; this.rejection = rejection;
        TransientCompletion = transientCompletion;
        FollowUp = followUp;
        Events = events ?? SessionTabEvents.None;
    }

    #endregion

    #region Actions - Commands

    /// Throws unless the command was accepted, the session still holds what it
    /// was prepared against, and a borrowed session still follows its owner.
    internal void RequireAccepted(SessionState current) {
        if (rejection is not null) throw new BrowserRuleException(rejection);
        if (!ReferenceEquals(current, Base)) throw new Rejected(new StaleCommand());
        owner.RequireCurrentBorrowedPolicy(Session);
        owner.RequirePendingTransient(TransientCompletion);
    }

    /// Commits the command. One that stages with its save is on disk with its
    /// journal before this returns; a failed save or stage changes nothing.
    public void Commit() => owner.Commit(this);

    internal NativeSessionReplacement Reserve() => owner.ReserveCommand(this);

    #endregion

    #region Mutators

    internal NativeSessionCommand StagedAs(SyncStaging? staging) {
        Staging = staging;
        return this;
    }

    #endregion
}
