using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Look` in the form the stored session keeps branding in, for a host that
/// keeps a look of its own across updates. It reads no state, so a host may
/// ask it without an app.
public sealed record StoreLook(SpaceBranding Look) : StandaloneQuery<StoredLook> {
    #region Actions - Answering

    internal override StoredLook Answer(StandaloneContext context) =>
        new(StoredSessionCodec.Encode(Look).ToJsonString());

    #endregion
}
