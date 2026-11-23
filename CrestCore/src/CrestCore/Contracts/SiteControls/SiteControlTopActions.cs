namespace CrestCore.Contracts;

/// The actions a person keeps on top of Site Controls on this device, first
/// to last: one to four, each offered on the device, and no action twice. The
/// device store keeps them and never syncs them, since each kind of device
/// offers actions of its own.
public sealed record SiteControlTopActions(IReadOnlyList<SiteControlAction> Actions) {
    #region Static Variables

    /// The most actions that sit on top.
    public const int MaximumCount = 4;

    /// The four of a device whose person never chose: Copy Link, Share, Pin
    /// Tab and Find in Page, which every device offers.
    public static SiteControlTopActions Default { get; } =
        new([SiteControlAction.CopyLink, SiteControlAction.Share, SiteControlAction.PinTab, SiteControlAction.FindInPage]);

    #endregion

    #region Actions - Rules

    /// The actions `kept` leaves on a device on `platform`: those the device
    /// offers, first to last, each once and at most four. When none is left,
    /// as when every kept action is one this build no longer offers, the
    /// defaults.
    internal static SiteControlTopActions Restored(IEnumerable<SiteControlAction> kept, DevicePlatform platform) {
        var actions = kept.Where(action => action.IsOffered(platform)).Distinct().Take(MaximumCount).ToList();
        return actions.Count == 0 ? Default : new(actions);
    }

    /// These actions with `action` in `slot`. An action already among them
    /// trades places with the one in `slot`; the slot after the last, while
    /// there is room, takes a new one. One the device on `platform` does not
    /// offer, or any other slot, leaves them as they are.
    internal SiteControlTopActions Placing(SiteControlAction action, int slot, DevicePlatform platform) {
        if (!action.IsOffered(platform)) return this;
        var actions = Actions.ToList();
        if (slot == actions.Count && actions.Count < MaximumCount && !actions.Contains(action)) return new([.. actions, action]);
        if (slot < 0 || slot >= actions.Count) return this;
        int from = actions.IndexOf(action);
        if (from >= 0) actions[from] = actions[slot];
        actions[slot] = action;
        return new(actions);
    }

    /// These actions with `action` moved or brought in at `index`, the others
    /// making room after it. Bringing one in while there are four lets the
    /// last go. One the device on `platform` does not offer leaves them as
    /// they are.
    internal SiteControlTopActions Moving(SiteControlAction action, int index, DevicePlatform platform) {
        if (!action.IsOffered(platform)) return this;
        var actions = Actions.Where(kept => kept != action).ToList();
        actions.Insert(Math.Clamp(index, 0, actions.Count), action);
        return new([.. actions.Take(MaximumCount)]);
    }

    /// These actions without `action`, unless it is the last one left.
    internal SiteControlTopActions Removing(SiteControlAction action) =>
        Actions.Count > 1 && Actions.Contains(action) ? new([.. Actions.Where(kept => kept != action)]) : this;

    #endregion

    #region Actions - Equality

    public bool Equals(SiteControlTopActions? other) => other is not null && Actions.SequenceEqual(other.Actions);

    public override int GetHashCode() => Actions.Aggregate(0, (hash, action) => HashCode.Combine(hash, action));

    #endregion
}

/// The actions on top of Site Controls changed on this device, or a launch
/// published them.
public sealed record SiteControlTopActionsChanged(SiteControlTopActions TopActions) : Change;
