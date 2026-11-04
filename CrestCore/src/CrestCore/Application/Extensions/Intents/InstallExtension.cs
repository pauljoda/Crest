using CrestCore.Application;

namespace CrestCore.Contracts;

/// Installs the extension `ExtensionId` on the engine of `Engine` as install
/// `InstallId`: in Space `SpaceId`, whose profile downloads the package, then
/// in each of `CopySpaceIds`, which the person's answer to the engine's
/// question may replace. The core publishes the install as
/// `ExtensionInstallChanged` as it moves on. The engine verifies the package
/// for each Space and asks whether to install it: the person answers the
/// first question unless the install is `PreApproved`, as an import's is, and
/// the consent given answers each copy that asks for the same package and
/// access. Each copy goes to a Space within reach when its turn comes, once
/// for each profile, and leaves out one whose profile already has the
/// extension, as a pre-approved install does for its first Space too.
public sealed record InstallExtension(Guid InstallId, Guid SpaceId, EngineKind Engine, string ExtensionId,
    IReadOnlyList<Guid> CopySpaceIds, bool PreApproved) : ExtensionIntent {
    #region Actions - Extensions

    /// Refused as `Extensions.Reachable` refuses the Space.
    internal override void Apply(Extensions extensions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var (space, engine) = extensions.Reachable(SpaceId, Engine);
        extensions.Start(new ExtensionInstall(InstallId, engine, space.Id, ExtensionId, CopySpaceIds, PreApproved), space,
            changes, issue);
    }

    #endregion
}
