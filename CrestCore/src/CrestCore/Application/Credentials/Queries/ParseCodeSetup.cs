using System.Text;

using CrestCore.Application;

namespace CrestCore.Contracts;

/// What `Text` sets up for one-time codes: a setup key a person typed or
/// pasted, or the link a site's QR code holds. The core keeps nothing of it.
[HoldsSecrets]
public sealed record ParseCodeSetup(string Text) : Query<ParsedCodeSetup> {
    #region Variables

    /// It reads only the text it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override ParsedCodeSetup Answer(CrestApp app) => OneTimeCodeSetup.Read(Text);

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("ParseCodeSetup { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    protected override bool PrintMembers(StringBuilder builder) {
        builder.Append($"Text = <{Text?.Length ?? 0} characters redacted>");
        return true;
    }

    #endregion
}
