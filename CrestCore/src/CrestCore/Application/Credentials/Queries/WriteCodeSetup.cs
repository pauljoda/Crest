using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Setup` as its canonical otpauth link, the form the app keeps and exports
/// it in: `ParseCodeSetup` reads the link back as an equal setup. The core
/// keeps nothing of either.
[HoldsSecrets]
public sealed record WriteCodeSetup(OneTimeCodeSetup Setup) : Query<CodeSetupLink> {
    #region Variables

    /// It reads only the setup it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override CodeSetupLink Answer(CrestApp app) {
        ArgumentNullException.ThrowIfNull(Setup);
        return Setup.Link();
    }

    #endregion
}
