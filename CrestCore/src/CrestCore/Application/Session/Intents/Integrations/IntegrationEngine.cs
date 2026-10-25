using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record IntegrationEngineChoice(EngineKind? Kind);

/// Resolves the engine a service's new pages use, without creating a page or
/// crossing a profile, private-workspace, lock or deletion boundary.
public sealed record IntegrationEngine(Guid WorkspaceId, Guid SpaceId, Guid ProfileId, SiteOrigin Origin) : Query<IntegrationEngineChoice> {
    #region Actions - Answering

    internal override IntegrationEngineChoice Answer(CrestApp app) {
        var workspace = app.Device.Workspace(WorkspaceId);
        workspace.RequirePreferenceOwner();
        var space = workspace.Editable(workspace.Current, SpaceId);
        if (space.ProfileId != ProfileId || !Origin.IsValid) throw new Rejected(new InvalidLiveFolder(SpaceId));
        var engines = app.Pages.Engines;
        var chosen = app.Device.ChosenEngine(SpaceId, Origin);
        return new((chosen is { } kind ? engines.Registered(kind) : null)?.Kind ?? engines.Default?.Kind);
    }

    #endregion
}
