using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// What a clear of a Space's open tabs took, which taking it back puts
    /// back: the Space as it stood before the clear `Id`, the open tabs the
    /// clear archived from it, and the tab the window that asked showed there.
    internal sealed record ClearMark(Guid Id, SpaceState Before, IReadOnlySet<Guid> TabIds, Guid? Shown);

    #endregion

    #region Static Variables

    /// The most clears a workspace remembers, the latest ones kept.
    internal const int RememberedClears = 20;

    #endregion

    #region Variables

    /// The clears this workspace made, latest last. Kept in memory only, as
    /// the undo that takes one back is.
    private readonly List<ClearMark> clears = [];

    #endregion

    #region Actions - Clearing

    /// The clear `id` names while the workspace remembers it, or null. The
    /// caller holds the gate.
    internal ClearMark? RememberedClear(Guid id) => clears.FirstOrDefault(mark => mark.Id == id);

    /// Remembers `mark`, a clear whose state just committed, as the latest
    /// clear, forgetting the oldest past the limit. The caller holds the gate.
    private void Remember(ClearMark mark) {
        clears.RemoveAll(remembered => remembered.Id == mark.Id);
        clears.Add(mark);
        if (clears.Count > RememberedClears) clears.RemoveAt(0);
    }

    #endregion
}
