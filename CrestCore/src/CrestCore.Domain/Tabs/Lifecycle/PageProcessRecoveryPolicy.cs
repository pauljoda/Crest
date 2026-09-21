namespace CrestCore.Domain;

/// How many times a renderer termination may be answered by reloading before
/// the page shows a failure instead of reloading forever.
public static class PageProcessRecoveryPolicy {
    #region Variables

    public const int MaximumAutomaticReloads = 2;

    #endregion

    #region Actions - Lifecycle

    public static ProcessRecoveryAction Decide(int consecutiveTerminations) {
        if (consecutiveTerminations < 1) throw new BrowserRuleException(BrowserRuleCodes.InvalidTerminationCount);
        return consecutiveTerminations <= MaximumAutomaticReloads
            ? ProcessRecoveryAction.Reload
            : ProcessRecoveryAction.ShowFailure;
    }

    #endregion
}
