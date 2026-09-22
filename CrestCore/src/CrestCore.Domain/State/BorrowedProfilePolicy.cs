namespace CrestCore.Domain;

/// A temporary workspace borrows one existing profile; it never replaces it.
public static class BorrowedProfilePolicy {
    #region Actions - State policy

    public static void RequireSource(Guid expectedSpace, Guid expectedProfile,
        Guid sourceSpace, Guid sourceProfile, bool available) {
        if (!available || expectedSpace != sourceSpace || expectedProfile != sourceProfile)
            throw new BrowserRuleException(BrowserRuleCodes.ProfileLeaseRevoked);
    }

    #endregion
}
