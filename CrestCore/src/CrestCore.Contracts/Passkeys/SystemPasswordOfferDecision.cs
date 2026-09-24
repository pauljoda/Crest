namespace CrestCore.Contracts;

/// Whether the save prompt offers the password to the system's Passwords app.
public sealed record SystemPasswordOfferDecision(bool Offers);
