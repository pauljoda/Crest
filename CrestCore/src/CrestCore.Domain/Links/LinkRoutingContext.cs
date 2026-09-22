namespace CrestCore.Domain;

/// The Spaces a link can reach: session order, the selected Space, and the
/// Spaces the caller cannot open right now, such as ones being deleted.
public sealed record LinkRoutingContext(IReadOnlyList<Guid> Spaces, Guid SelectedSpaceId, IReadOnlySet<Guid> Unavailable) {
    #region Actions - Availability

    public bool IsAvailable(Guid space) => !Unavailable.Contains(space) && Spaces.Contains(space);

    /// The selected Space when it can open, else the first Space that can.
    public Guid Fallback() => IsAvailable(SelectedSpaceId) ? SelectedSpaceId
        : Spaces.Where(space => !Unavailable.Contains(space)).Select(space => (Guid?)space).FirstOrDefault() ?? SelectedSpaceId;

    #endregion
}
