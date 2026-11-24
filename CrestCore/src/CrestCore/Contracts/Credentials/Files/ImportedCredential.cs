namespace CrestCore.Contracts;

/// A password another browser keeps, row `RowNumber` of what it brings, with
/// the name it shows for it, the note it keeps beside it and the `otpauth://`
/// link its one-time codes come from, each null when it has none. The link is
/// carried as written; the core reads nothing of it.
[HoldsSecrets]
public sealed record ImportedCredential(int RowNumber, string? DisplayName, CredentialOrigin Origin, string Username, string Password,
    string? Note, string? OneTimeCodeLink) {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("ImportedCredential { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"RowNumber = {RowNumber}, Origin = {Origin}, Username = <redacted>, Password = <redacted>, Note = <redacted>, OneTimeCodeLink = <redacted>");
        return true;
    }

    #endregion
}
