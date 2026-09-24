using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The core's typed application API. An intent changes state and answers the
/// changes it published, or throws `Rejected`; a query answers without
/// changing anything. Each area handles its own intents and queries. One lock
/// serializes every call on this instance.
///
/// Changes the core starts itself, such as a finished save, a session commit
/// or an engine's report, wait in a pending batch the host drains after its
/// wake callback runs. An intent answers that batch first, so no older change
/// arrives after a newer one. Commands for engine bindings wait in a queue that
/// is delivered once the lock is released.
public sealed partial class CrestApp : IDisposable {
    #region Variables

    private readonly Lock gate = new();
    private readonly Downloads downloads = new();
    private readonly Credentials credentials = new();
    private readonly Search search = new();
    private readonly ContentBlocking contentBlocking = new();
    private readonly Links links = new();
    /// This device's windows and what each shows.
    private readonly Device device;
    /// The pages this device hosts, and the engines that host them.
    private readonly Pages pages;
    /// The time session intents are stamped with.
    private readonly IClock clock;
    /// Where the identities the core gives new records come from.
    private readonly IIdSource ids;

    #endregion

    #region Constructors

    /// A core that keeps everything in memory.
    public CrestApp() : this(new AppConfiguration(null)) { }

    /// A core configured by the host. With a storage directory it opens the
    /// session file there and loads the session it holds; throws `Rejected`
    /// when the file cannot be used.
    public CrestApp(AppConfiguration configuration) : this(configuration, new SystemClock(), new SystemIdSource()) { }

    /// A core that reads the time from `clock` and draws new identities from `ids`.
    internal CrestApp(AppConfiguration configuration, IClock clock, IIdSource ids) {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(clock);
        ArgumentNullException.ThrowIfNull(ids);
        this.clock = clock;
        this.ids = ids;
        if (configuration.StorageDirectory is not { } directory) {
            device = new(storage: null, DeviceRecords.Empty, Announce, RequestTurn);
            pages = new(device, engines, clock, ids);
            return;
        }
        storage = SessionStorage.Open(directory, Announce, out var loaded);
        device = new(storage, storage.Device, Announce, RequestTurn);
        pages = new(device, engines, clock, ids);
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

    /// The changes still pending when the intent ran and those it published
    /// there, in the order they happened, then the changes the intent itself
    /// published. An intent that does not apply to the current state publishes
    /// none. Engine commands the intent caused have been delivered when this
    /// returns, unless it runs inside a delivery.
    public IReadOnlyList<Change> Send(Intent intent) {
        ArgumentNullException.ThrowIfNull(intent);
        IReadOnlyList<Change> published;
        lock (gate) {
            var changes = new ChangeFeed();
            switch (intent) {
                case DownloadIntent download:
                    downloads.Handle(download, changes);
                    break;
                case AdoptLegacySession adoption:
                    Adopt(adoption, changes);
                    break;
                case WindowIntent window:
                    device.Handle(window, changes);
                    break;
                case PageIntent page:
                    pages.Handle(page, changes, Issue);
                    break;
                case SessionIntent session:
                    device.Workspace(session.WorkspaceId).Handle(session, clock.Now, ids);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "No area handles this intent.");
            }
            published = [.. Drain(), .. changes.Published];
        }
        Deliver();
        WakeForRequestedTurn();
        return published;
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
                CanTearOff tearOff => device.Answer(tearOff),
                FallbackTab fallback => Window.Answer(fallback),
                PendingSave => new PendingSaveRevision(storage?.PendingRevision is { } revision ? checked((long)revision) : null),
                CanSend check => Permission(check.Intent),
                _ => throw new ArgumentOutOfRangeException(nameof(query), query.GetType().Name, "No area answers this query.")
            };
            return (TAnswer)answer;
        }
    }

    /// Whether the core would accept a session intent now: the rule that would
    /// refuse it, or none. The identities a check draws are never used.
    private SendPermission Permission(Intent intent) {
        if (intent is not SessionIntent session)
            throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "Only a session intent can be checked.");
        try {
            device.Workspace(session.WorkspaceId).Check(session, clock.Now, new SystemIdSource());
            return new(Refusal: null);
        } catch (Rejected refused) {
            return new(refused.Rejection);
        }
    }

    #endregion

    #region Actions - Workspaces

    /// Attaches a session this device's windows may show and answers the
    /// workspace identity the core gave it; a session already attached keeps
    /// its own.
    public Guid AttachWorkspace(NativeSessionAuthority session) => device.Attach(session);

    #endregion

    #region Actions - Lifetime

    /// Stages and saves any accepted revision still pending and closes the
    /// session file. The stored session accepts no edits afterwards, and no
    /// engine binding hears from the core again.
    public void Dispose() {
        lock (gate) engines.Clear();
        SessionSync?.Stop();
        Session?.Release();
        storage?.Dispose();
    }

    #endregion
}
