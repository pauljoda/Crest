using CrestCore.Application;

namespace CrestCore.Contracts;

/// Install `InstallId` has its package, which the engine keeps until the core
/// ends the install.
public sealed record ExtensionDownloaded(Guid InstallId) : ExtensionEvent {
    #region Actions - Extensions

    /// The package goes into the install's first Space.
    internal override void Apply(Extensions extensions, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (extensions.Running(InstallId, engine) is not { HasPackage: false } install) return;
        install.Downloaded();
        extensions.Advance(install, changes, issue);
    }

    #endregion
}
