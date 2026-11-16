using CrestCore.Application;

namespace CrestCore.Contracts;

/// Blocks at `Level` on every page in every Space. A level that blocks turns
/// each catalog list on or off as it chooses, replacing the lists the person
/// turned themselves, whatever level came before; choosing the level in force
/// again restores its lists. Off blocks nothing and leaves the lists as they
/// are.
public sealed record SetContentBlockingLevel(ContentBlockingLevel Level) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => {
        if (!app.Device.SetContentBlockingLevel(Level)) return false;
        app.Filters.SubscriptionsChanged();
        return true;
    });

    #endregion
}
