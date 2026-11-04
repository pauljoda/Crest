using CrestCore.Application;

namespace CrestCore.Contracts;

/// Install `InstallId` installed its package in the profile `ProfileId` names.
public sealed record ExtensionInstalled(Guid InstallId, Guid ProfileId) : ExtensionEvent {
    #region Actions - Extensions

    /// The install goes on to its next Space, or ends once none is left.
    internal override void Apply(Extensions extensions, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (extensions.Running(InstallId, engine) is not { } install || install.InstallingProfile != ProfileId) return;
        install.Installed();
        extensions.Advance(install, changes, issue);
    }

    #endregion
}
