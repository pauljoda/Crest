namespace CrestCore.Contracts;

/// The tabs and folders a person selected together in a window's sidebar.
/// `TabIds` and `FolderIds` name what they picked; a tab or folder inside a
/// picked folder goes with that folder. `MemberTabIds` are the tabs the window
/// saw the selection hold when the person acted: each picked tab and every tab
/// inside a picked folder. The core refuses a selection that no longer holds
/// exactly those tabs, and acts on it in the order the Space's sidebar lists
/// it, whatever order the lists name it in.
public sealed record TabSelection(IReadOnlyList<Guid> TabIds, IReadOnlyList<Guid> FolderIds, IReadOnlyList<Guid> MemberTabIds);
