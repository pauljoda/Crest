namespace CrestCore.Contracts;

/// <summary>
/// Which session a Space browses with instead of its own profile, and when a person
/// last changed that on any device. A Sub-Space names its <see cref="PrimaryId"/>, the
/// Space whose session it joined, and browses with <see cref="SharedProfileId"/>, that
/// session's profile. A primary that took over a deleted primary's session names no
/// primary and browses with the profile it took over. A Space that left its group
/// names neither and keeps the time it left, so an older copy that still names the
/// group cannot bring it back.
/// </summary>
public sealed record SpaceMembership(Guid? PrimaryId, Guid? SharedProfileId, DateTimeOffset ModifiedAt) {
    #region Variables

    /// Whether the Space joined another Space's session.
    internal bool IsSubSpace => PrimaryId is not null;

    #endregion

    #region Actions - Groups

    /// The membership of a Sub-Space of `primary`, browsing with the profile
    /// `primary` browses with, as chosen at `modifiedAt`.
    internal static SpaceMembership Joining(SpaceState primary, DateTimeOffset modifiedAt) =>
        new(primary.Id, primary.ProfileId, modifiedAt);

    /// The membership of a primary that browses with `profileId`, a session it
    /// took over from a primary that went away, as chosen at `modifiedAt`.
    internal static SpaceMembership Leading(Guid profileId, DateTimeOffset modifiedAt) => new(null, profileId, modifiedAt);

    /// The membership of a Space that left its group at `modifiedAt` and
    /// browses with its own profile again.
    internal static SpaceMembership Leaving(DateTimeOffset modifiedAt) => new(null, null, modifiedAt);

    #endregion
}
