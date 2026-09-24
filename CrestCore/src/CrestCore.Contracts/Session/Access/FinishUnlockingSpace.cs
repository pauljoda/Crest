namespace CrestCore.Contracts;

/// Answers the pending request `RequestId` for a Space with whether the
/// device owner authenticated. Only the request still pending may finish: a
/// lock cancels it, so a late answer never unlocks the Space for a newer one.
/// A refusal ends the request and grants nothing.
public sealed record FinishUnlockingSpace(Guid SpaceId, Guid RequestId, bool Authenticated) : SpaceAccessIntent;
