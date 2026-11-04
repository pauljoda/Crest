using CrestCore.Application;

namespace CrestCore.Contracts;

/// The extensions installed in the profile `ProfileId` names, as the engine
/// lists them now: when the core asked, and whenever they change after.
public sealed record ExtensionsListed(Guid ProfileId, IReadOnlyList<InstalledExtension> Extensions) : ExtensionEvent {
    #region Actions - Extensions

    internal override void Apply(Extensions extensions, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) =>
        extensions.Record(engine, ProfileId, Extensions, changes);

    #endregion
}
