namespace CrestCore.Contracts;

/// One Space of a manual setup: the Space `SpaceId` with its own profile
/// `ProfileId`, whether the setup makes it, the name and look it takes, and,
/// for a Sub-Space, the primary `PrimaryId` of the group whose session it
/// shares. A name left blank stays blank here, as the person is typing it.
public sealed record SetupDraftSpace(Guid SpaceId, Guid ProfileId, bool IsNew, SpaceCustomization Customization,
    Guid? PrimaryId = null) {
    #region Variables

    /// The name the Space shows and takes once the setup is applied: the one
    /// given, trimmed, or "Untitled Space" for a blank one.
    [Resolved]
    public string ShownName => SpaceCustomization.Resolved(Customization.Name);

    #endregion

    #region Actions - Setup

    /// The existing Space `space` as a setup starts from it, with its name,
    /// look and group.
    internal static SetupDraftSpace Existing(SpaceState space) =>
        new(space.Id, space.OwnProfileId, IsNew: false, space.Customization, space.PrimaryId);

    /// The Space with its look in `look`, keeping its name, symbol and colors.
    internal SetupDraftSpace Restyled(SetupLook look) => this with { Customization = look.Applying(Customization) };

    #endregion
}
