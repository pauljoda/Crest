using CrestCore.Application;

namespace CrestCore.Contracts;

/// Makes `Change` to the extension `ExtensionId` the engine of `Engine`
/// installed in Space `SpaceId`'s profile, which every Space browsing with
/// that profile shares. The engine lists the profile again once it changed.
public sealed record ChangeExtension(Guid SpaceId, EngineKind Engine, string ExtensionId, ExtensionChange Change)
    : ExtensionIntent {
    #region Actions - Extensions

    /// Refused as `Extensions.Reachable` refuses the Space, and, once the
    /// engine listed the profile, with `UnknownExtension` for an extension it
    /// did not list and `ExtensionNotChangeable` for one the person may not
    /// change.
    internal override void Apply(Extensions extensions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var (space, engine) = extensions.Reachable(SpaceId, Engine);
        if (extensions.Listed(engine, space.ProfileId) is { } listed) {
            var extension = listed.FirstOrDefault(extension => extension.Id == ExtensionId)
                ?? throw new Rejected(new UnknownExtension(ExtensionId));
            if (!extension.Changeable) throw new Rejected(new ExtensionNotChangeable(ExtensionId));
        }
        issue(engine, new ChangeEngineExtension(space.ProfileId, ExtensionId, Change));
    }

    #endregion
}
