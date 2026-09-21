namespace CrestCore.Domain;

/// A temporary workspace borrows one existing profile; it never replaces it.
public static class BorrowedProfilePolicy {
    #region Actions - State policy

    public static void RequireSource(SpaceId expectedSpace, ProfileId expectedProfile,
        SpaceId sourceSpace, ProfileId sourceProfile, bool available) {
        if (!available || expectedSpace != sourceSpace || expectedProfile != sourceProfile)
            throw new BrowserRuleException("profile_lease_revoked");
    }

    #endregion
}
