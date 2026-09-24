namespace CrestCore.Contracts;

/// <summary>What a workspace's session is: the persistent session this device
/// keeps, a private one that keeps nothing, or a borrowed one that shows a Space
/// of another workspace with its own tabs and keeps nothing.</summary>
public enum WorkspaceKind { Persistent, Private, Borrowed }
