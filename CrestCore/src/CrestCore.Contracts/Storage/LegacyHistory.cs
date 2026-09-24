namespace CrestCore.Contracts;

/// One Space's history as an installed release kept it beside the session.
public sealed record LegacyHistory(Guid SpaceId, byte[] Entries);
