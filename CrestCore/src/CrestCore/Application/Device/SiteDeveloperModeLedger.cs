using CrestCore.Contracts;

namespace CrestCore.Application;

#region Types

/// One site's Developer Mode choice: on or off. A choice the device store
/// keeps names no Space and holds for every Space; one a memory-only Space
/// made names that Space.
internal sealed record SiteDeveloperModeChoice(Guid? SpaceId, SiteOrigin Origin, bool IsOn);

#endregion

/// Developer Mode choices in the order they were made, least recent first.
/// Past `Maximum`, the least recently chosen goes. Not thread-safe: the device
/// lock guards it.
internal sealed class SiteDeveloperModeLedger {
    #region Static Variables

    /// The most choices a ledger holds.
    public const int Maximum = 512;

    #endregion

    #region Variables

    private readonly List<SiteDeveloperModeChoice> choices = [];

    /// Every choice, least recent first.
    public IReadOnlyList<SiteDeveloperModeChoice> Choices => choices;

    #endregion

    #region Actions - Choices

    /// Replaces whatever the ledger held with `kept`.
    public void Restore(IEnumerable<SiteDeveloperModeChoice> kept) {
        choices.Clear();
        foreach (var choice in kept) Choose(choice);
    }

    /// Records `choice` as the most recent for its Space and origin, and says
    /// whether the ledger changed.
    public bool Choose(SiteDeveloperModeChoice choice) {
        if (choices.Count > 0 && choices[^1] == choice) return false;
        choices.RemoveAll(held => held.SpaceId == choice.SpaceId && held.Origin == choice.Origin);
        choices.Add(choice);
        if (choices.Count > Maximum) choices.RemoveRange(0, choices.Count - Maximum);
        return true;
    }

    /// Whether Developer Mode is chosen on or off for `origin` in `spaceId`,
    /// or null when no choice is.
    public bool? Chosen(Guid? spaceId, SiteOrigin origin) =>
        choices.LastOrDefault(choice => choice.SpaceId == spaceId && choice.Origin == origin)?.IsOn;

    /// Forgets an explicit choice, so the site follows the default again.
    public bool Forget(Guid? spaceId, SiteOrigin origin) =>
        choices.RemoveAll(choice => choice.SpaceId == spaceId && choice.Origin == origin) > 0;

    #endregion
}
