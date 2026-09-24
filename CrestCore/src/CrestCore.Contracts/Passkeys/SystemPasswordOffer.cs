namespace CrestCore.Contracts;

/// Whether a save prompt goes on to offer the password to the system's
/// Passwords app: only when the Space opted in, the launch can, and the window
/// is not private.
public sealed record SystemPasswordOffer(bool SpaceOffersSystemPasswords, SystemPasswordWriteThroughAvailability Availability,
    bool IsPrivateBrowsing) : Query<SystemPasswordOfferDecision>;
