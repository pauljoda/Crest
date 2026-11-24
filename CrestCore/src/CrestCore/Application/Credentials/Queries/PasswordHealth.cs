using System.Text;

using CrestCore.Application;

namespace CrestCore.Contracts;

/// The health of `Credentials`, the passwords a Space keeps: for each, the
/// concerns that apply to it (see `PasswordConcern`) and, for a reused one,
/// the others sharing its password. The answer names no password, and it is
/// worked out afresh for each question: the core keeps nothing of either.
/// Refused with `DuplicateCredential` when two passwords share an identity.
[HoldsSecrets]
[MessageLimit(MessageLimitAttribute.SessionBytes)]
public sealed record PasswordHealth(IReadOnlyList<CheckedCredential> Credentials) : Query<PasswordHealthReport> {
    #region Variables

    /// It reads the passwords it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override PasswordHealthReport Answer(CrestApp app) {
        ArgumentNullException.ThrowIfNull(Credentials);
        if (Credentials.Select(credential => credential.Id).Distinct().Count() != Credentials.Count)
            throw new Rejected(new DuplicateCredential());
        var sharing = Credentials.ToLookup(credential => credential.Password, StringComparer.Ordinal);
        return new([.. Credentials.Select(credential => {
            Guid[] others = [.. sharing[credential.Password].Where(other => other.Id != credential.Id).Select(other => other.Id)];
            return new CredentialHealth(credential.Id, PasswordConcern.Of(credential, others), others);
        })]);
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("PasswordHealth { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    protected override bool PrintMembers(StringBuilder builder) {
        builder.Append($"Credentials = {Credentials.Count}");
        return true;
    }

    #endregion
}
