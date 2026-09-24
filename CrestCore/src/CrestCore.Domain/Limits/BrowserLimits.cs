using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The capacity limits the domain enforces, in one place. Native callers read
/// them through the `limits` policy operation instead of keeping copies.
public static class BrowserLimits {
    #region Variables

    public const int PinnedTabs = TabPlacement.PinnedCapacity;
    public const int Folders = FolderTree.MaximumCount;
    public const int FolderDepth = FolderTree.MaximumDepth;
    public const int HistoryEntries = HistoryPolicy.MaximumEntries;
    public const int SplitMembers = BrowserTabCollection.MaximumSplitMembers;
    public const int BrandColors = SpaceBrandingPolicy.MaximumColorCount;
    public const int CrestPalette = SpaceBrandingPolicy.MaximumCrestPaletteCount;
    public const int Spaces = WorkspaceImportPolicy.MaximumSpaces;
    public const int TabsPerSpace = BrowserSpace.MaximumTabs;

    #endregion
}
