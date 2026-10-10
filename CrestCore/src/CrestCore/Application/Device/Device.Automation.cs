using CrestCore.Contracts;

namespace CrestCore.Application;

/// This device's automation preferences, which the device store keeps and
/// never syncs, and what they let local tools reach.
internal sealed partial class Device {
    #region Variables

    private AutomationPreferences automation = AutomationPreferences.Off;
    internal AutomationPreferences Automation {
        get {
            lock (gate) return automation;
        }
    }

    #endregion

    #region Actions - Automation intents

    /// Runs one automation intent, publishing the preferences when they
    /// changed.
    public void Handle(AutomationIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Keeps the preferences `revise` makes of the device's own, and publishes
    /// them when they changed.
    internal void ReviseAutomation(ChangeFeed changes, Func<AutomationPreferences, AutomationPreferences> revise) {
        lock (gate) Revise(revise(automation), changes);
    }

    /// Forgets a deleted Space in the automation preferences.
    public void ForgetAutomation(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) Revise(automation.Forgetting(spaceId), changes);
    }

    /// Keeps `revised` and publishes it when it differs from the preferences
    /// the device holds. The caller holds the device lock.
    private void Revise(AutomationPreferences revised, ChangeFeed changes) {
        if (revised.Equals(automation)) return;
        automation = revised;
        storage?.EnqueueDevice(Records());
        changes.Publish(new AutomationPreferencesChanged(automation));
    }

    #endregion

    #region Actions - Reach

    /// Whether tools may be allowed to reach `spaceId`: a Space of the
    /// person's own session that is not being deleted. Called without the
    /// device lock, since it reads the session.
    internal bool OffersToAutomation(Guid spaceId) =>
        Persistent() is (_, var authority) && authority.Current.Spaces.Any(space => space.Id == spaceId) && !authority.IsDeleting(spaceId);

    /// What local tools may reach now: nothing while automation is off, and
    /// otherwise each allowed Space of the person's own session that is not
    /// being deleted, in the session's order. Called without the device lock,
    /// since it reads the session.
    internal AutomationReachList AutomationReach() {
        var preferences = Automation;
        if (!preferences.IsOn || Persistent() is not (var workspaceId, var authority)) return new(null, []);
        // The session's own locks are taken only once the device's is released.
        var spaces = authority.Current.Spaces.Where(space => preferences.SpaceIds.Contains(space.Id) && !authority.IsDeleting(space.Id))
            .Select(space => new AutomationSpace(space.Id, space.Settings.Name, authority.IsLocked(space)));
        return new(workspaceId, [.. spaces]);
    }

    #endregion
}
