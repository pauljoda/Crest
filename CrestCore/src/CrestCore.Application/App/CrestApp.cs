using CrestCore.Contracts;

namespace CrestCore.Application;

/// The core's typed application API. An intent changes state and answers the
/// changes it published, or throws `Rejected`; a query answers without
/// changing anything. Each area handles its own intents and queries. One lock
/// serializes every call on this instance.
public sealed class CrestApp {
    #region Variables

    private readonly Lock gate = new();
    private readonly Downloads downloads = new();

    #endregion

    #region Actions - Intents

    /// The changes the intent published. An intent that does not apply to the
    /// current state publishes none.
    public IReadOnlyList<Change> Send(Intent intent) {
        ArgumentNullException.ThrowIfNull(intent);
        lock (gate) {
            var changes = new ChangeFeed();
            switch (intent) {
                case DownloadIntent download:
                    downloads.Handle(download, changes);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "No area handles this intent.");
            }
            return changes.Published;
        }
    }

    #endregion

    #region Actions - Queries

    public TAnswer Query<TAnswer>(Query<TAnswer> query) {
        ArgumentNullException.ThrowIfNull(query);
        lock (gate) {
            throw new ArgumentOutOfRangeException(nameof(query), query.GetType().Name, "No area answers this query.");
        }
    }

    #endregion
}
