using CrestCore.Contracts;

namespace CrestCore.Application;

/// Whether each site's pages show Developer Mode. The device store keeps the
/// choices made in the persistent session's Spaces, which hold for every
/// Space; a choice made in any other Space (private, seeded, or one no
/// attached session holds) holds for that Space alone and lives in memory
/// until the process ends. Such a Space still follows the kept choices.
internal sealed partial class Device {
    #region Variables

    /// The persistent session's choices, which the device store keeps.
    private readonly SiteDeveloperModeLedger keptDeveloperModes = new();
    /// Every other Space's choices, which live as long as the process.
    private readonly SiteDeveloperModeLedger passingDeveloperModes = new();

    #endregion

    #region Actions - Site Developer Mode intents

    /// Chooses Developer Mode on or off for `origin` from now on, or forgets
    /// the choice when `isOn` is null, as a choice made in `spaceId`: for
    /// every Space when the device store keeps its choices, or for that Space
    /// alone. Answers whether anything changed. Throws `Rejected` for an
    /// origin that is not valid or a locked Space.
    public bool ChooseDeveloperMode(Guid spaceId, SiteOrigin origin, bool? isOn) {
        ArgumentNullException.ThrowIfNull(origin);
        if (!origin.IsValid) throw new Rejected(new InvalidSiteOrigin(origin));
        var (keeps, locked) = ChoiceScope(spaceId);
        if (locked) throw new Rejected(new SpaceLocked(spaceId));
        lock (gate) {
            var ledger = keeps ? keptDeveloperModes : passingDeveloperModes;
            Guid? scope = keeps ? null : spaceId;
            bool changed = isOn is { } on ? ledger.Choose(new(scope, origin, on)) : ledger.Forget(scope, origin);
            if (changed && keeps) storage?.EnqueueDevice(Records());
            return changed;
        }
    }

    #endregion

    #region Actions - Site Developer Mode queries

    /// Whether Developer Mode is chosen on or off for `origin` in `spaceId`,
    /// or null when no choice is. Called without the device lock, since it
    /// reads the sessions.
    public bool? ChosenDeveloperMode(Guid spaceId, SiteOrigin origin) {
        ArgumentNullException.ThrowIfNull(origin);
        lock (gate) {
            if (keptDeveloperModes.Choices.Count == 0 && passingDeveloperModes.Choices.Count == 0) return null;
        }
        var (keeps, _) = ChoiceScope(spaceId);
        lock (gate) return (keeps ? null : passingDeveloperModes.Chosen(spaceId, origin)) ?? keptDeveloperModes.Chosen(null, origin);
    }

    #endregion
}
