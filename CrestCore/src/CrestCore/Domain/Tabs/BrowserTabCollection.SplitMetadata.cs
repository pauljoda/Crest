namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Split metadata

    /// A split copied into new tabs keeps its name, icon, tint and collapse,
    /// each recorded as chosen now so the copy's fields win over nothing older.
    public void CopySplitMetadata(Guid source, Guid copy, DateTimeOffset now) {
        if (splitGroups.FirstOrDefault(group => group.Id == source) is not { } metadata) return;
        var changedAt = BrowserEditTimestamp.Normalize(now);
        splitGroups.Add(metadata with {
            Id = copy,
            TitleModifiedAt = changedAt,
            IconModifiedAt = changedAt,
            TintModifiedAt = changedAt,
            CollapseModifiedAt = changedAt
        });
    }

    /// Gives `destination` what was chosen for the splits `groups` names, as
    /// it was chosen, for splits whose tabs move there whole, under the
    /// identity `renamed` gives a split whose own the destination already
    /// uses. This Space drops its own once no tab of theirs is left; see
    /// `PruneSplitMetadata`.
    private void HandSplitMetadataTo(BrowserTabCollection destination, IReadOnlySet<Guid> groups,
        IReadOnlyDictionary<Guid, Guid> renamed) =>
        destination.splitGroups.AddRange(splitGroups.Where(group => groups.Contains(group.Id))
            .Select(group => renamed.TryGetValue(group.Id, out var fresh) ? group with { Id = fresh } : group));

    /// Drops what was chosen for splits no tab belongs to any longer.
    public void PruneSplitMetadata() {
        var retained = tabs.Where(tab => tab.SplitGroupId is not null).Select(tab => tab.SplitGroupId!.Value).ToHashSet();
        splitGroups.RemoveAll(group => !retained.Contains(group.Id));
    }

    #endregion
}
