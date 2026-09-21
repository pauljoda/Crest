namespace CrestCore.Domain;

/// How many times a renderer termination may be answered by reloading before
/// the page shows a failure instead of reloading forever.
public static class PageProcessRecoveryPolicy {
    public const int MaximumAutomaticReloads = 2;

    public static ProcessRecoveryAction Decide(int consecutiveTerminations) {
        if (consecutiveTerminations < 1) throw new BrowserRuleException("invalid_termination_count");
        return consecutiveTerminations <= MaximumAutomaticReloads
            ? ProcessRecoveryAction.Reload
            : ProcessRecoveryAction.ShowFailure;
    }
}
