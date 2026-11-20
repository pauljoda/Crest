namespace CrestCore.Contracts;

/// How many of each thing the core keeps: folders in a Space and how deep
/// they nest, history entries per Space, members of a split, colors in a
/// Space's branding and its crest palette, Spaces in a workspace, tabs in a
/// Space, records in the sync journal, bytes in a password file an import
/// reads, and bytes in a filter list.
public sealed record CapacityLimits(
    int Folders,
    int FolderDepth,
    int HistoryEntries,
    int SplitMembers,
    int BrandColors,
    int CrestPalette,
    int Spaces,
    int TabsPerSpace,
    int SyncRecords,
    int CredentialFileBytes,
    int FilterListBytes);
