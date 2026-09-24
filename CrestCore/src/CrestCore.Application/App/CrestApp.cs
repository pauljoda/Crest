using CrestCore.Contracts;

namespace CrestCore.Application;

/// The core's typed application API. An intent changes state and answers the
/// changes it published, or throws `Rejected`; a query answers without
/// changing anything. Each area handles its own intents and queries. One lock
/// serializes every call on this instance.
///
/// Changes the core starts itself, such as a finished save, wait in a pending
/// batch the host drains after its wake callback runs.
public sealed partial class CrestApp : IDisposable {
    #region Variables

    private readonly Lock gate = new();
    private readonly Downloads downloads = new();
    private readonly Credentials credentials = new();
    private readonly Search search = new();
    private readonly ContentBlocking contentBlocking = new();
    private readonly Links links = new();

    #endregion

    #region Constructors

    /// A core that keeps everything in memory.
    public CrestApp() : this(new AppConfiguration(null)) { }

    /// A core configured by the host. With a storage directory it opens the
    /// session file there and loads the session it holds; throws `Rejected`
    /// when the file cannot be used.
    public CrestApp(AppConfiguration configuration) {
        ArgumentNullException.ThrowIfNull(configuration);
        if (configuration.StorageDirectory is not { } directory) return;
        storage = SessionStorage.Open(directory, Announce, out var loaded);
        try {
            if (loaded.Session is { } stored) Establish(stored, loaded.Journal, loaded.LegacySelection);
        } catch (Exception error) {
            storage.Dispose();
            if (error is Rejected) throw;
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        }
    }

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
            object answer = query switch {
                DownloadProgress progress => downloads.Answer(progress),
                DownloadRisk risk => downloads.Answer(risk),
                CredentialCapture capture => credentials.Answer(capture),
                CredentialFill fill => credentials.Answer(fill),
                CredentialSaveCheck check => credentials.Answer(check),
                MostRecentCredential recency => credentials.Answer(recency),
                CredentialSaveMatch match => credentials.Answer(match),
                CredentialSave save => credentials.Answer(save),
                StrongPassword password => credentials.Answer(password),
                PasskeyAccess access => credentials.Answer(access),
                SystemPasswordWriteThrough writeThrough => credentials.Answer(writeThrough),
                SystemPasswordOffer offer => credentials.Answer(offer),
                CustomSearchEngineAdmission admission => search.Answer(admission),
                BalancedProtectionRules rules => contentBlocking.Answer(rules),
                ExternalLinkRoute route => links.Answer(route),
                QuickWindowSite site => links.Answer(site),
                _ => throw new ArgumentOutOfRangeException(nameof(query), query.GetType().Name, "No area answers this query.")
            };
            return (TAnswer)answer;
        }
    }

    #endregion

    #region Actions - Lifetime

    /// Saves any accepted revision still pending and closes the session file.
    /// The stored session accepts no edits afterwards.
    public void Dispose() {
        Session?.Release();
        storage?.Dispose();
    }

    #endregion
}
