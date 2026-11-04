using CrestCore.Application;

namespace CrestCore.Contracts;

/// Install `InstallId` could not download its package through the profile
/// `ProfileId` names, or could not install it there, for `Reason`.
public sealed record ExtensionInstallFailed(Guid InstallId, Guid ProfileId, ExtensionInstallFailure Reason) : ExtensionEvent {
    #region Actions - Extensions

    /// A failed download, or the first Space's install, ends the install; a
    /// copy that failed leaves the others to go.
    internal override void Apply(Extensions extensions, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (extensions.Running(InstallId, engine) is not { } install) return;
        if (install.InstallingProfile is null) {
            if (!install.HasPackage) extensions.End(install, Reason, changes, issue);
            return;
        }
        if (install.InstallingProfile != ProfileId) return;
        if (install.InstallingFirst) {
            extensions.End(install, Reason, changes, issue);
            return;
        }
        install.Skipped();
        extensions.Advance(install, changes, issue);
    }

    #endregion
}
