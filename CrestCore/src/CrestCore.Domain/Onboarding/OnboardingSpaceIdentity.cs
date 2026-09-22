namespace CrestCore.Domain;

/// A Space and the website profile it owns, compared as one identity.
public readonly record struct OnboardingSpaceIdentity(Guid SpaceId, Guid ProfileId);
