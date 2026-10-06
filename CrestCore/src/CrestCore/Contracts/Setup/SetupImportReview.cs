namespace CrestCore.Contracts;

/// The review of what one browser brings, one Space at a time: each Space's
/// choices, the pinned tabs that move to a saved folder because their
/// destination holds no more, and the Space the person is looking at.
public sealed record SetupImportReview(ImportSource Source, IReadOnlyList<SetupReviewSpace> Spaces, IReadOnlyList<Guid> OverflowTabIds,
    Guid? ShownSpaceId) {
    #region Variables

    /// Whether the review brings any Space.
    [Resolved]
    public bool HasIncludedSpaces => Spaces.Any(space => space.Included);

    /// How many tabs the review brings.
    [Resolved]
    public int IncludedTabCount => Spaces.Where(space => space.Included).Sum(space => space.IncludedTabIds.Count);

    /// The Space after the one the person is looking at, which Next shows, or
    /// null on the last Space.
    [Resolved]
    public Guid? NextSpaceId {
        get {
            int shown = Spaces.Select(space => space.Source.Id).ToList().IndexOf(ShownSpaceId ?? Guid.Empty);
            if (shown < 0) return Spaces.FirstOrDefault()?.Source.Id;
            return shown + 1 < Spaces.Count ? Spaces[shown + 1].Source.Id : null;
        }
    }

    /// Whether the person is looking at the last Space, where Next imports.
    [Resolved]
    public bool ShowsLastSpace => Spaces.Count > 0 && ShownSpaceId == Spaces[^1].Source.Id;

    /// How many saved passwords the review brings.
    [Resolved]
    public int IncludedPasswordCount => Spaces.Where(space => space.Included && space.IncludesPasswords).Sum(space => space.PasswordCount);

    /// How many extensions the review installs.
    [Resolved]
    public int IncludedExtensionCount => Spaces.Sum(space => space.BroughtExtensions.Count);

    #endregion
}
