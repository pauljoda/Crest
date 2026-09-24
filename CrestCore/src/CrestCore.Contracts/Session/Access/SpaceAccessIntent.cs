namespace CrestCore.Contracts;

/// An intent about which Spaces this process may show: unlocking one once the
/// device owner authenticates, or locking Spaces again. A grant covers one
/// Space's profile in every workspace that shows it, lives only as long as the
/// process, and is never saved or synced. The platform presents the
/// authentication prompt itself.
public abstract record SpaceAccessIntent : Intent;
