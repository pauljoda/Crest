using CrestCore.Application;

namespace CrestCore.Contracts;

/// The one-time code `Setup` makes at `Now`, in seconds since 1970, and the
/// times it is valid from and until. The core keeps nothing of either.
[HoldsSecrets]
public sealed record OneTimeCode(OneTimeCodeSetup Setup, double Now) : Query<OneTimeCodeReading> {
    #region Variables

    /// It reads only the setup it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override OneTimeCodeReading Answer(CrestApp app) {
        ArgumentNullException.ThrowIfNull(Setup);
        return Setup.ReadingAt(Now);
    }

    #endregion
}
