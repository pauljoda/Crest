namespace CrestCore.Contracts;

#region Rejections

/// The workspace borrows its one Space from the workspace that owns the
/// Space's profile, which changes the Space's settings and makes, orders and
/// deletes Spaces.
public sealed record BorrowedProfileRequiresOwner(Guid WorkspaceId) : Rejection;

/// Deleting the Space would leave the workspace without one.
public sealed record CannotDeleteLastSpace() : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest needs at least one Space.";

    #endregion
}

/// The order does not name each of the workspace's Spaces exactly once.
public sealed record InvalidSpaceOrder() : Rejection;

/// The Space a deletion names to lead the group of the primary it deletes is
/// not one of that group's Sub-Spaces that stay.
public sealed record InvalidNewPrimary(Guid SpaceId) : Rejection;

/// Only a private workspace starts over.
public sealed record NotPrivateWorkspace(Guid WorkspaceId) : Rejection;

/// The Space leads Sub-Spaces, or browses with a session it took over from a
/// primary that was deleted, so it cannot join another group.
public sealed record PrimaryCannotJoin(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "A Space with Sub-Spaces can't become a Sub-Space.";

    #endregion
}

/// Only a Sub-Space separates from its group; a primary leaves it only when it
/// is deleted.
public sealed record PrimaryCannotSeparate(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Only a Sub-Space can be separated.";

    #endregion
}

/// A private window's Space is a fresh session every time, which no Space shares.
public sealed record PrivateSpaceCannotShare(Guid WorkspaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Private windows can't have Sub-Spaces.";

    #endregion
}

/// The workspace already holds a Space with this identity.
public sealed record SpaceAlreadyExists(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That Space already exists.";

    #endregion
}

/// The workspace already holds `Limit` Spaces, or would hold more.
public sealed record SpaceLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Crest supports up to %lld Spaces.";

    #endregion
}

/// The Space's deletion is not the one the intent names: another operation
/// began it, or none did.
public sealed record WrongDeletionOperation(Guid SpaceId) : Rejection;

#endregion
