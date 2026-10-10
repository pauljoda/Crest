namespace CrestCore.Contracts;

#region Types

/// A tool the person approved: the name it gave when it connected, and the
/// program that connected, by its path. Any program at that path that gives
/// that name is the same tool.
public sealed record AutomationTool(string Name, string Path);

#endregion

/// Whether local tools such as scripts and coding agents may control Crest on
/// this device, the Spaces of the person's own session they may reach, and
/// the tools the person approved. The device store keeps them and never syncs
/// them. Each edit answers the revised preferences, or throws the rule that
/// refuses it.
public sealed record AutomationPreferences(bool IsOn, IReadOnlyList<Guid> SpaceIds, IReadOnlyList<AutomationTool> Tools) {
    #region Static Variables

    /// The preferences of a device that never chose any: off, reaching no
    /// Space and trusting no tool.
    internal static AutomationPreferences Off { get; } = new(IsOn: false, [], []);

    public const int MaximumTools = 32;
    public const int MaximumToolName = 64;
    public const int MaximumToolPath = 1024;

    #endregion

    #region Actions - Spaces

    /// Allows or stops allowing tools to reach `spaceId`. An allowed Space
    /// keeps its place, and a newly allowed one goes after the others.
    public AutomationPreferences Allowing(Guid spaceId, bool allowed) {
        var others = SpaceIds.Where(candidate => candidate != spaceId);
        if (!allowed) return this with { SpaceIds = [.. others] };
        return SpaceIds.Contains(spaceId) ? this : this with { SpaceIds = [.. others, spaceId] };
    }

    /// A deleted Space is no longer one tools may reach.
    public AutomationPreferences Forgetting(Guid spaceId) => Allowing(spaceId, allowed: false);

    #endregion

    #region Actions - Tools

    /// Trusts `tool` from now on. A tool approved before keeps its place.
    /// Refused with `InvalidAutomationTool` for an empty or overlong name or a
    /// path that is not absolute, and with `AutomationToolsFull` past
    /// `MaximumTools`.
    public AutomationPreferences Approving(AutomationTool tool) {
        ArgumentNullException.ThrowIfNull(tool);
        if (string.IsNullOrWhiteSpace(tool.Name) || tool.Name.Length > MaximumToolName || !tool.Path.StartsWith('/')
            || tool.Path.Length > MaximumToolPath)
            throw new Rejected(new InvalidAutomationTool(MaximumToolName, MaximumToolPath));
        if (Tools.Contains(tool)) return this;
        if (Tools.Count >= MaximumTools) throw new Rejected(new AutomationToolsFull(MaximumTools));
        return this with { Tools = [.. Tools, tool] };
    }

    /// Stops trusting `tool`; the next time it connects, the person is asked
    /// again.
    public AutomationPreferences Forgetting(AutomationTool tool) => this with { Tools = [.. Tools.Where(candidate => candidate != tool)] };

    #endregion

    #region Actions - Equality

    public bool Equals(AutomationPreferences? other) => other is not null
        && IsOn == other.IsOn && SpaceIds.SequenceEqual(other.SpaceIds) && Tools.SequenceEqual(other.Tools);

    public override int GetHashCode() => HashCode.Combine(IsOn, SpaceIds.Count, Tools.Count);

    #endregion
}
