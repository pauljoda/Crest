namespace CrestCore.Contracts;

/// A saved password a Space exports, with the name it shows, if any, the note
/// the file keeps beside it, and the `otpauth://` link its one-time codes come
/// from, if any.
[HoldsSecrets]
public sealed record ExportedCredential(Guid Id, CredentialOrigin Origin, string Username, string? DisplayName, string Password,
    string Note, string? OneTimeCodeLink) {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("ExportedCredential { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Id = {Id}, Origin = {Origin}, Username = <redacted>, Password = <redacted>, Note = <redacted>, OneTimeCodeLink = <redacted>");
        return true;
    }

    #endregion
}
