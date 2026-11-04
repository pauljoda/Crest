using CrestCore.Application;

namespace CrestCore.Contracts;

/// The engine verified install `InstallId`'s package for the profile it
/// installs in, and asks whether to install it, which waits for the core's
/// `SettleExtensionInstall`.
public sealed record ExtensionInstallRequested(Guid PromptId, Guid InstallId, ExtensionInstallQuestion Question) : ExtensionEvent {
    #region Actions - Extensions

    /// A question no install the core runs is installing for is declined at
    /// once; see `Extensions.Ask` for the others.
    internal override void Apply(Extensions extensions, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (extensions.Running(InstallId, engine) is not { InstallingProfile: not null } install) {
            issue(engine, new SettleExtensionInstall(PromptId, Accepted: false, WithholdsSiteAccess: false));
            return;
        }
        extensions.Ask(install, PromptId, Question, changes, issue);
    }

    #endregion
}
