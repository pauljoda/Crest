namespace CrestCore.Contracts;

/// The first rule a session breaks that keeps a workspace from holding it.
public enum SeedFlaw {
    /// It is not a session in the stored format.
    Unreadable,
    /// A Space, its profile, one of its tabs or a Space deletion has no identity.
    MissingIdentity,
    /// Two Spaces share an identity.
    DuplicateSpace,
    /// Two Spaces share a profile, which would share its website data across them.
    SharedProfile,
    /// Two tabs share an identity.
    DuplicateTab,
    /// A Space deletion names a Space, or a profile, the session does not hold,
    /// or names one Space twice.
    UnknownDeletion
}
