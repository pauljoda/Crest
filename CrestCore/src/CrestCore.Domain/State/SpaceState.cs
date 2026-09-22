namespace CrestCore.Domain;

public sealed record SpaceState(Guid Id, Guid ProfileId, string Name, bool RequiresAuthentication,
    IReadOnlyList<TabState> Tabs, IReadOnlyList<FolderState> Folders,
    IReadOnlyList<ArchiveState> Archive, IReadOnlyList<HistoryVisit> History, Guid? SelectedTabId,
    SearchPreferences? Search = null, bool SupportsDeviceAuthentication = true, RetentionPreferences? Retention = null, ContentBlockingPolicy ContentBlocking = ContentBlockingPolicy.Balanced);
