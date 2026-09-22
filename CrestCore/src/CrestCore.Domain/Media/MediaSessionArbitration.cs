namespace CrestCore.Domain;

/// Published sessions in display order, as indices into the caller's list, and
/// the one session that owns the system's Now Playing, if any.
public sealed record MediaSessionArbitration(IReadOnlyList<int> Order, int? NowPlaying);
