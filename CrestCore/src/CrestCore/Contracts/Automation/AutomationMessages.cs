namespace CrestCore.Contracts;

#region Queries

/// What local tools may reach now. With automation off there is no workspace
/// and no Space. Otherwise `WorkspaceId` is the person's own session, and
/// `Spaces` lists each allowed Space it holds that is not being deleted, in
/// the session's order.
public sealed record AutomationReachList(Guid? WorkspaceId, IReadOnlyList<AutomationSpace> Spaces) {
    #region Actions - Equality

    public bool Equals(AutomationReachList? other) =>
        other is not null && WorkspaceId == other.WorkspaceId && Spaces.SequenceEqual(other.Spaces);

    public override int GetHashCode() => HashCode.Combine(WorkspaceId, Spaces.Count);

    #endregion
}

/// A Space a local tool may reach, and whether this process holds no grant to
/// show it. A tool sees a locked Space's name and nothing in it.
public sealed record AutomationSpace(Guid SpaceId, string Name, bool IsLocked);

#endregion

#region Changes

/// This device's automation preferences changed.
public sealed record AutomationPreferencesChanged(AutomationPreferences Preferences) : Change;

#endregion

#region Rejections

/// Only a Space of the person's own session may be reached by a tool: never a
/// private window's, a borrowed workspace's, or one being deleted.
public sealed record AutomationSpaceUnavailable(Guid SpaceId) : Rejection;

/// A tool's name is empty or longer than `MaximumName` characters, or its path
/// is not absolute or longer than `MaximumPath` characters.
public sealed record InvalidAutomationTool(int MaximumName, int MaximumPath) : Rejection;

/// No tool more can be approved: there are already `Maximum`.
public sealed record AutomationToolsFull(int Maximum) : Rejection;

#endregion
