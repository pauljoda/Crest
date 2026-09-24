namespace CrestCore.Contracts;

/// The session a workspace was asked to open from is one the core cannot hold.
public sealed record InvalidSeed(SeedFlaw Flaw) : Rejection;
