namespace CrestCore.Domain;

/// The store's instructions for one report. A rejected report changes nothing.
/// `EvictOldest` is how many of the oldest remembered identities to forget
/// once this one is recorded. A published session supersedes every other
/// document under the same tab, keeps `Ordinal` for ordering, and the store
/// continues from `NextOrdinal`.
public sealed record MediaSessionEventDecision(bool Accepted, int EvictOldest, MediaSessionDisposition Disposition,
    bool SupersedesTabSiblings, ulong? Ordinal, ulong NextOrdinal, bool ClearsDismissal);
