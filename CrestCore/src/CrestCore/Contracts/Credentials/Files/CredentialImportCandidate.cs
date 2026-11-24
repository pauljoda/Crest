namespace CrestCore.Contracts;

/// One password an import offers for an account: the first row that brings
/// it, with the username, name, note and `otpauth://` link that row spells,
/// each null when it has none, and what importing it does. Importing it over a
/// saved password keeps the saved note and link where the row has none.
[HoldsSecrets]
public sealed record CredentialImportCandidate(int RowNumber, string Username, string? DisplayName, string Password, string? Note,
    string? OneTimeCodeLink, CredentialImportEffect Effect) {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("CredentialImportCandidate { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"RowNumber = {RowNumber}, Username = <redacted>, Password = <redacted>, Note = <redacted>, ")
            .Append($"OneTimeCodeLink = <redacted>, Effect = {Effect.Name}");
        return true;
    }

    #endregion
}
