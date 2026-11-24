namespace CrestCore.Contracts;

/// A saved password whose health a `PasswordHealth` question checks: its
/// identity, the origin it is saved for, its username and its password.
[HoldsSecrets]
public sealed partial record CheckedCredential(Guid Id, CredentialOrigin Origin, string Username, string Password) {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("CheckedCredential { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Id = {Id}, Origin = {Origin}, Username = <redacted>, Password = <redacted>");
        return true;
    }

    #endregion
}
