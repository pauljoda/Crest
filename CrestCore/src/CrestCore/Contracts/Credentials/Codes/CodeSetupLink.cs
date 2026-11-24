using System.Text;

namespace CrestCore.Contracts;

/// A one-time code setup as its canonical otpauth link, which holds its key.
[HoldsSecrets]
public sealed record CodeSetupLink(string Link) {
    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CodeSetupLink { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append("Link = <redacted>");
        return true;
    }

    #endregion
}
