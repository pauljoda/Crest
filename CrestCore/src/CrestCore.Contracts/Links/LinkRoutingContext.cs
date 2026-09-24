namespace CrestCore.Contracts;

/// The Spaces a link can reach: session order, the selected Space, and the
/// Spaces the caller cannot open right now, such as ones being deleted.
public sealed record LinkRoutingContext(IReadOnlyList<Guid> Spaces, Guid SelectedSpaceId, IReadOnlyList<Guid> UnavailableSpaceIds) {
    #region Actions - Availability

    public bool IsAvailable(Guid space) => !UnavailableSpaceIds.Contains(space) && Spaces.Contains(space);

    /// The selected Space when it can open, else the first Space that can.
    public Guid Fallback() => IsAvailable(SelectedSpaceId) ? SelectedSpaceId
        : Spaces.Where(space => !UnavailableSpaceIds.Contains(space)).Select(space => (Guid?)space).FirstOrDefault() ?? SelectedSpaceId;

    #endregion
}
