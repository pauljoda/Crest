using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lists the extensions the engine of `Engine` installed in Space `SpaceId`'s
/// profile: the core publishes what it already knows as
/// `InstalledExtensionsChanged`, and the engine lists the profile, loading it
/// when nothing has, and follows it from then on.
public sealed record ListExtensions(Guid SpaceId, EngineKind Engine) : ExtensionIntent {
    #region Actions - Extensions

    /// Refused as `Extensions.Reachable` refuses the Space.
    internal override void Apply(Extensions extensions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var (space, engine) = extensions.Reachable(SpaceId, Engine);
        extensions.List(engine, space.ProfileId, changes, issue);
    }

    #endregion
}
