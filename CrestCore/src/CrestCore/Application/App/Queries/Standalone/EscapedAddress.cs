using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Spelling` as `WebAddress.Escaped` escapes it, which a host reads as a URL
/// when its own parser would escape the escapes a page spelled again. It reads
/// no state, so a host may ask it without an app.
public sealed record EscapedAddress(string Spelling) : StandaloneQuery<string> {
    #region Actions - Answering

    internal override string Answer(StandaloneContext context) => new WebAddress(Spelling).Escaped;

    #endregion
}
