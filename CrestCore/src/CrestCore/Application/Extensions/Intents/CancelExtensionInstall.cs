using CrestCore.Application;

namespace CrestCore.Contracts;

/// Stops install `InstallId`, as the person closing its review does: its
/// download, the question it waits on and the copies still to go. An install
/// that already ended changes nothing.
public sealed record CancelExtensionInstall(Guid InstallId) : ExtensionIntent {
    #region Actions - Extensions

    internal override void Apply(Extensions extensions, ChangeFeed changes, Action<Engine, EngineCommand> issue) =>
        extensions.Cancel(InstallId, changes, issue);

    #endregion
}
