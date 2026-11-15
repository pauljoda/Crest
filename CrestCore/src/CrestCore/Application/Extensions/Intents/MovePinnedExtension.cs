using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves the pinned extension `ExtensionId` of Space `SpaceId`'s profile to
/// just before the pinned extension `BeforeExtensionId`, or to the end of the
/// pins when that is null. Every Space browsing with the profile shows its
/// pins in that order. The engine lists the profile again once it changed.
public sealed record MovePinnedExtension(Guid SpaceId, EngineKind Engine, string ExtensionId, string? BeforeExtensionId)
    : ExtensionIntent {
    #region Actions - Extensions

    /// Refused as `Extensions.Reachable` refuses the Space, and, once the
    /// engine listed the profile, with `UnknownExtension` for an extension it
    /// did not list. A move onto the extension itself changes nothing.
    internal override void Apply(Extensions extensions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var (space, engine) = extensions.Reachable(SpaceId, Engine);
        if (ExtensionId == BeforeExtensionId) return;
        if (extensions.Listed(engine, space.ProfileId) is { } listed
            && listed.All(extension => extension.Id != ExtensionId)) {
            throw new Rejected(new UnknownExtension(ExtensionId));
        }
        issue(engine, new MoveEngineExtensionPin(space.ProfileId, ExtensionId, BeforeExtensionId));
    }

    #endregion
}
