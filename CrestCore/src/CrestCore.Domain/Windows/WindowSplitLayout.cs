namespace CrestCore.Domain;

/// A split group's stored column count and the group's live member count,
/// null when no Space renders the group as a split any longer.
public readonly record struct WindowSplitLayout(Guid GroupId, int Columns, int? LiveMembers);
