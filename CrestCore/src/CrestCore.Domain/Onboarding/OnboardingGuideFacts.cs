namespace CrestCore.Domain;

/// The Spaces the Getting Started guide depends on, observed before and after
/// the person unlocked its target. <paramref name="PreviewFirst"/> is the first
/// Space of a manual plan previewed against the current session, null when
/// there is no plan or the preview failed; <paramref name="Locked"/> is the lock
/// state of the Space the guide would open in.
public readonly record struct OnboardingGuideFacts(OnboardingSpaceIdentity Target,
    OnboardingSpaceIdentity? OriginalFirst, OnboardingSpaceIdentity? CurrentFirst,
    OnboardingSpaceIdentity? OriginalTarget, OnboardingSpaceIdentity? CurrentTarget,
    OnboardingSpaceIdentity? PreviewFirst, bool HasManualPlan, bool Locked);
