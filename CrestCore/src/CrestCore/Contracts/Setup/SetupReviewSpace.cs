namespace CrestCore.Contracts;

/// What the person chose for one Space an import brings, and what those
/// choices mean: whether it comes in, the existing Space it joins or none for
/// a new Space, the name and look it takes, the tabs it brings and the
/// placements they move to, its saved passwords, and the extensions it offers
/// with those left on. `DuplicateTabIds` are its tabs the destination
/// already holds, which it leaves out until the person asks for them;
/// `MatchedTabIds` are the destination's tabs it matches.
public sealed record SetupReviewSpace(SpaceState Source, bool Included, Guid? DestinationId, SpaceCustomization Customization,
    IReadOnlyList<Guid> IncludedTabIds, IReadOnlyList<Guid> DuplicateTabIds, IReadOnlyList<Guid> MatchedTabIds,
    IReadOnlyList<TabPlacementChoice> Placements, bool IncludesPasswords, int PasswordCount, IReadOnlyList<ImportExtension> Extensions,
    IReadOnlyList<string> IncludedExtensionIds) {
    #region Variables

    /// The name the Space shows and takes once imported: the one chosen,
    /// trimmed, or "Untitled Space" for a blank one.
    [Resolved]
    public string ShownName => SpaceCustomization.Resolved(Customization.Name);

    /// Whether the passwords that belong with the Space come in with it.
    [Resolved]
    public bool BringsPasswords => Included && IncludesPasswords;

    /// The extensions that install in the Space's destination once it is
    /// imported: those the person left on, in the order the Space offers them,
    /// when the Space comes in.
    [Resolved]
    public IReadOnlyList<ImportExtension> BroughtExtensions => Included
        ? [.. Extensions.Where(extension => IncludedExtensionIds.Contains(extension.ExtensionId))] : [];

    /// Whether the Space comes in as a new Space, taking room in the
    /// workspace, rather than joining one it holds.
    internal bool MakesNewSpace => Included && DestinationId is null;

    #endregion
}
