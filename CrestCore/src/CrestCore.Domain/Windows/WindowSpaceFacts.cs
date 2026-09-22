namespace CrestCore.Domain;

/// What a window needs to know about one Space of the session it reflects.
/// <paramref name="HasWindowTab"/> is true when the tab the window last chose
/// for this Space is still one of its tabs; <paramref name="HasSpaceSelection"/>
/// likewise for the session's own selection. <paramref name="IsCaptured"/> is
/// true when the window recorded this Space, so a missing tab means the person
/// left it empty.
public readonly record struct WindowSpaceFacts(Guid Id, bool HasWindowTab, bool IsCaptured,
    bool HasSpaceSelection, bool HasTabs);
