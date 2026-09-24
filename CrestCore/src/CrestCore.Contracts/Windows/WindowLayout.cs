namespace CrestCore.Contracts;

/// The sidebar a window kept: its width and whether it was presented, each
/// absent when the window never set it.
public sealed record WindowLayout(Guid WindowId, double? SidebarWidth, bool? SidebarIsPresented);
