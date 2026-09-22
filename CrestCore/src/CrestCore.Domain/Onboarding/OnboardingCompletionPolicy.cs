namespace CrestCore.Domain;

/// When finishing setup opens the Getting Started guide, and whether the
/// workspace it was prepared for still stands once the guide's Space unlocks.
public static class OnboardingCompletionPolicy {
    #region Actions - Completion

    /// A rerun always reopens the guide; a first run opens it once per
    /// install. Other entry points complete without it. A private workspace
    /// never consumes the install's setup completion.
    public static OnboardingCompletion Decide(OnboardingEntryPoint entryPoint, bool hasCompletedSetup, bool isPrivateBrowsing) {
        if (isPrivateBrowsing) return OnboardingCompletion.SourceChanged;
        return entryPoint == OnboardingEntryPoint.Rerun || entryPoint == OnboardingEntryPoint.FirstRun && !hasCompletedSetup
            ? OnboardingCompletion.OpenGuide : OnboardingCompletion.Complete;
    }

    /// Whether the guide may open after authentication. With a manual plan,
    /// the first Space and the target must be unchanged and the plan must
    /// still put the target first; without one, the target must still be
    /// first. The target must be unlocked in both cases.
    public static bool ConfirmsGuide(OnboardingGuideFacts facts) {
        if (facts.Locked) return false;
        if (!facts.HasManualPlan) return facts.CurrentFirst == facts.Target;
        return facts.CurrentFirst == facts.OriginalFirst && facts.CurrentTarget == facts.OriginalTarget
            && facts.PreviewFirst == facts.Target;
    }

    #endregion
}
