namespace CrestCore.Contracts;

/// Where a link opened from outside Crest goes: the first enabled route whose
/// Space can open, else the external-link destination preference. A Space in
/// `LockedSpaceIds` is never unlocked on such a link's behalf; the link opens
/// in a Quick Window on an unlocked Space instead.
public sealed record ExternalLinkRoute(string Url, LinkRoutingPreferences Preferences, LinkRoutingContext Context,
    IReadOnlyList<Guid> LockedSpaceIds) : Query<ExternalLinkPlacement>;
