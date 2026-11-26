using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The device's filter lists: the copy of each one the core downloaded, when
/// each is due again, and the WebKit content rule lists compiled from the ones
/// the device subscribes to. The copies live as files in a `ContentFilter`
/// folder beside the session file, never in the session, its sync or its
/// recovery checkpoint; a core without a storage directory keeps them in
/// memory. Converting lists into content rules runs on a worker, never under
/// the app's lock, and announces `ContentRuleListsChanged` when the new rules
/// are ready. Until a list arrives, Crest's own baseline rules block. The
/// library also keeps the link-tracking list up to date, which only cleans
/// copied links.
internal sealed partial class FilterLibrary {
    #region Types

    /// What the device holds of one download: its text's digest, or null
    /// before a download succeeded; the validators that download gave; when the
    /// copy was last brought up to date and when it is due again; how long the
    /// list says a copy stays current; how many attempts in a row failed; and,
    /// for a list, what it calls itself.
    private sealed record Copy(string? Digest, string? EntityTag, string? LastModified, DateTimeOffset? UpdatedAt,
        DateTimeOffset DueAt, TimeSpan Refresh, int Failures, string? Title = null, bool TooLarge = false) {
        #region Types

        /// How the library's state file spells a copy's members.
        private static class Key {
            public const string Digest = "digest";
            public const string EntityTag = "entityTag";
            public const string LastModified = "lastModified";
            public const string UpdatedAt = "updatedAt";
            public const string DueAt = "dueAt";
            public const string Refresh = "refresh";
            public const string Failures = "failures";
            public const string Title = "title";
            public const string TooLarge = "tooLarge";
        }

        #endregion

        #region Actions - Coding

        /// The copy as the library's state file keeps it.
        public JsonObject Encoded() => new() {
            [Key.Digest] = Digest,
            [Key.EntityTag] = EntityTag,
            [Key.LastModified] = LastModified,
            [Key.UpdatedAt] = UpdatedAt?.ToUnixTimeSeconds(),
            [Key.DueAt] = DueAt.ToUnixTimeSeconds(),
            [Key.Refresh] = (long)Refresh.TotalSeconds,
            [Key.Failures] = Failures,
            [Key.Title] = Title,
            [Key.TooLarge] = TooLarge
        };

        /// The copy the state file kept in `state`; a member it lacks takes
        /// its default, and a missing refresh takes `usualRefresh`.
        public static Copy Decoded(JsonObject state, TimeSpan usualRefresh) {
            long? updated = state[Key.UpdatedAt]?.GetValue<long>();
            return new(state[Key.Digest]?.GetValue<string>(), state[Key.EntityTag]?.GetValue<string>(),
                state[Key.LastModified]?.GetValue<string>(), updated is { } seconds ? DateTimeOffset.FromUnixTimeSeconds(seconds) : null,
                DateTimeOffset.FromUnixTimeSeconds(state[Key.DueAt]?.GetValue<long>() ?? 0),
                TimeSpan.FromSeconds(state[Key.Refresh]?.GetValue<long>() ?? (long)usualRefresh.TotalSeconds),
                state[Key.Failures]?.GetValue<int>() ?? 0, state[Key.Title]?.GetValue<string>(),
                state[Key.TooLarge]?.GetValue<bool>() ?? false);
        }

        /// The digest a kept state names, read before the rest so a copy
        /// whose text is gone can be left out.
        public static string? DigestIn(JsonObject state) => state[Key.Digest]?.GetValue<string>();

        #endregion
    }

    /// One thing the library downloads: a catalog list or one the person
    /// added, named on the device by `Name` and on the wire by `Id`.
    private sealed record Download(string Name, Guid Id, string Url);

    #endregion

    #region Static Variables

    /// The longest list the core keeps, within the 16 MiB an intent may carry.
    public const int MaximumListBytes = 15 * 1024 * 1024;
    /// The most rules the core takes from one list; a list with more is
    /// refused, as one too large is.
    public const int MaximumListRules = 300_000;

    /// The most rules one compiled list holds; WebKit refuses more than 150,000.
    private const int RulesPerList = 70_000;

    /// Names the converter: change it whenever the content filter's crate
    /// changes what lists convert to, so devices convert theirs again. The
    /// keys also hold the baseline rules' digest, so changing those does too.
    private const string RulesRevision = "adblock-0.13.5+css-validation;own-hiding-only;trusted-chosen";

    private static readonly string BaselineDigest =
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(BaselineRules)));

    private const string IdentifierPrefix = "com.pauldavis.crest.content-filter.";

    /// How the person's own filters are named among the lists' inputs.
    private const string CustomFiltersName = "my-filters";

    /// The uBlock Origin release whose scriptlets and redirect resources the
    /// filter loads, as Crest publishes them for download, and how they are
    /// named on the device and on the wire.
    private const string ResourcesRelease = "ublock-resources-1.75.4";
    /// The SHA-256 of the resources `Scripts/control-plane/ublock-resources`
    /// builds for that release, which the core requires before it loads them:
    /// code it runs in pages comes only from a reviewed pin.
    private const string ResourcesSHA256 = "e9cbfd34a2708f446a114dc17e8aba8e772541c0999b4a29950df0368fa3ad09";
    private const string ResourcesName = "resources";
    internal static readonly Guid ResourcesId = new("6f0b8c52-3d1e-4f7a-9a51-7c2d4e8b1f30");
    public const string PublishedResourcesUrl =
        "https://github.com/crest-browser/Crest/releases/download/" + ResourcesRelease + "/ublock-resources.json";

    /// AdGuard's URL Tracking filter, in its build for uBlock Origin, and how
    /// it is named on the device and on the wire. The device keeps it while
    /// it cleans copied links, whatever level ad blocking blocks at, and reads
    /// only its `$removeparam` filters, beside Crest's own baseline: it never
    /// shows among the lists, nor reaches the content rules or the engine
    /// filter.
    private const string LinkTrackingName = "link-tracking";
    internal static readonly Guid LinkTrackingId = new("d637b5d3-f321-4f63-98ce-9632840b1af8");
    public const string LinkTrackingUrl = FilterList.AdGuard + "17.txt";

    private static readonly TimeSpan ShortestRefresh = TimeSpan.FromHours(12);
    private static readonly TimeSpan LongestRefresh = TimeSpan.FromDays(7);
    private static readonly TimeSpan UsualRefresh = TimeSpan.FromDays(4);
    private static readonly TimeSpan FirstRetry = TimeSpan.FromMinutes(30);
    private static readonly TimeSpan LongestRetry = TimeSpan.FromHours(12);
    /// The most times a failed download's retry wait doubles from the first.
    private const int MostRetryDoublings = 16;
    /// How much later than its refresh a copy is due at most, as a share of
    /// the refresh, so devices do not all ask at once.
    private const double RefreshSpread = 0.1;
    /// How long a download the core handed out keeps the list from being
    /// handed out again.
    private static readonly TimeSpan FetchLease = TimeSpan.FromMinutes(10);

    /// The `!#if` tokens that hold in WebKit's content rules: WebKit's own, and
    /// uBlock Origin's own syntax, which the engine reads.
    private static readonly string[] WebKitConditions = ["env_safari", "ext_ublock"];

    /// Crest's own rules: third-party loads from well-known advertising and
    /// analytics hosts, which block before any list arrives and beside them,
    /// and video players that leave their place in the page to float over it
    /// as the reader scrolls on.
    private const string BaselineRules = """
        ! Title: Crest baseline
        ##.jw-flag-floating .jw-wrapper
        ||doubleclick.net^$third-party
        ||googleadservices.com^$third-party
        ||googlesyndication.com^$third-party
        ||google-analytics.com^$third-party
        ||googletagmanager.com^$third-party
        ||ads-twitter.com^$third-party
        ||analytics.twitter.com^$third-party
        ||scorecardresearch.com^$third-party
        ||quantserve.com^$third-party
        ||hotjar.com^$third-party
        ||segment.io^$third-party
        ||segment.com^$third-party
        ||mixpanel.com^$third-party
        ||amplitude.com^$third-party
        ||clarity.ms^$third-party
        ||nr-data.net^$third-party
        ||taboola.com^$third-party
        ||outbrain.com^$third-party
        ||snap.licdn.com^$third-party
        """;

    #endregion

    #region Variables

    private readonly Lock gate = new();
    private readonly string? folder;
    private readonly IReadOnlySet<string> conditions;
    private readonly IReadOnlySet<string> engineConditions;
    private readonly IReadOnlyList<string> languages;
    /// Where the scriptlet and redirect resources come from, and the digest
    /// they must have.
    private readonly Download resourcesDownload;
    private readonly string resourcesDigest;
    private readonly Download linkTrackingDownload = new(LinkTrackingName, LinkTrackingId, LinkTrackingUrl);
    private readonly Func<FilterPreferences> preferences;
    private readonly Action<Change> announce;
    private readonly IClock clock;
    private readonly Dictionary<string, Copy> copies = [];
    /// Without a folder: each list's text, and each compiled list's source.
    private readonly Dictionary<string, string> heldTexts = [];
    private readonly Dictionary<string, string> heldSources = [];
    private readonly Dictionary<string, DateTimeOffset> leases = [];
    /// The link-tracking list's filters, with the digest of the copy they
    /// were read from, so each copy is read once.
    private (string Digest, ParameterFilterList Filters)? linkTracking;
    private ContentRuleListSet published = new([]);
    private string? publishedKey;
    /// The set in force before the published one, whose rules the device
    /// keeps for a switch back.
    private (string Key, ContentRuleListSet Set)? previous;
    /// The rules being converted, and whether the inputs changed meanwhile.
    private string? buildingKey;
    private bool rebuildWanted;
    /// A list changed while other downloads were out: the lists convert once
    /// the last of them reports.
    private bool rebuildDeferred;
    /// The slot an engine that checks each request itself checks against,
    /// made when one first asks for it, and the compiled filter, which is in
    /// force in it and answers what a document hides on every engine.
    private ContentFilterSlot? slot;
    private ContentFilter? engine;
    /// How many readers use the engine outside the lock, and the engines a
    /// rebuild replaced while any did, freed once the last reader is done.
    private int engineReaders;
    private readonly List<ContentFilter> retiredEngines = [];
    private string? engineKey;
    private string? buildingEngineKey;
    private bool engineRebuildWanted;
    /// The workers converting the rules or compiling the engine filter that
    /// may still run, including one a newer worker replaced while it
    /// announced its rules; whether the library stopped, after which none
    /// starts; and whether it closed, after which nothing writes in the folder.
    private readonly List<Task> workers = [];
    private bool stopped;
    private bool closed;

    #endregion

    #region Constructors

    /// The library for a core keeping its session in `storageDirectory`, or in
    /// memory without one. `languages` decide the regional lists that are on
    /// by default; `preferences` answers the person's own choices, the lists
    /// they added and their own filters. Tests may name resources of their own
    /// with their digest, `resourcesDigest`.
    public FilterLibrary(string? storageDirectory, DevicePlatform platform, IReadOnlyList<string>? languages,
        Func<FilterPreferences> preferences, Action<Change> announce, IClock clock, string? resourcesUrl = null,
        string? resourcesDigest = null) {
        ArgumentNullException.ThrowIfNull(platform);
        ArgumentNullException.ThrowIfNull(preferences);
        ArgumentNullException.ThrowIfNull(announce);
        ArgumentNullException.ThrowIfNull(clock);
        folder = storageDirectory is null ? null : Path.Combine(storageDirectory, "ContentFilter");
        conditions = new HashSet<string>([.. WebKitConditions, .. platform.FilterConditions]);
        engineConditions = new HashSet<string>([.. platform.EngineConditions, .. platform.FilterConditions]);
        this.languages = languages ?? [];
        this.preferences = preferences;
        resourcesDownload = new(ResourcesName, ResourcesId, resourcesUrl ?? PublishedResourcesUrl);
        this.resourcesDigest = resourcesDigest ?? ResourcesSHA256;
        this.announce = announce;
        this.clock = clock;
        RestoreState();
    }

    #endregion

    #region Actions - Lists

    /// Whether the device subscribes to `list`: as the person turned it, or as
    /// the level they chose turns it.
    private bool IsOn(FilterList list, FilterPreferences chosen) =>
        chosen.Choices.TryGetValue(list, out bool isOn) ? isOn : list.IsOnByDefault(chosen.Level, languages);

    /// How a catalog list is named on the wire: the same on every device.
    internal static Guid IdOf(FilterList list) =>
        new(SHA256.HashData(Encoding.UTF8.GetBytes("crest.filter-list:" + list.Name)).AsSpan(0, 16));

    /// How a list the person added is named on the device.
    private static string NameOf(CustomFilterList list) => "custom-" + list.Id.ToString("N");

    private static string HostOf(string url) => Uri.TryCreate(url, UriKind.Absolute, out var address) ? address.Host : url;

    private static string Digest(string text) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(text)));

    /// The lists the device subscribes to: the catalog's, then the person's.
    private IEnumerable<Download> Lists(FilterPreferences chosen) =>
        FilterList.All.Where(list => IsOn(list, chosen)).Select(list => new Download(list.Name, IdOf(list), list.Source))
            .Concat(chosen.CustomLists.Where(list => list.IsOn).Select(list => new Download(NameOf(list), list.Id, list.Url)));

    /// Every download in force: the lists the device subscribes to, the
    /// resources, and the link-tracking list while the device cleans copied
    /// links.
    private IEnumerable<Download> Downloads(FilterPreferences chosen) {
        var downloads = Lists(chosen).Append(resourcesDownload);
        return chosen.CleansCopiedLinks ? downloads.Append(linkTrackingDownload) : downloads;
    }

    /// Ad blocking as the settings show it: the level, whether the person
    /// turned any catalog list against it, every list, and their own filters.
    public FilterLists States() {
        var chosen = preferences();
        bool customized = chosen.Level.BlocksContent
            && FilterList.All.Any(list => IsOn(list, chosen) != list.IsOnByDefault(chosen.Level, languages));
        lock (gate) {
            var catalog = FilterList.All.Select(list => copies.TryGetValue(list.Name, out var copy)
                ? new FilterListState(list, IsOn(list, chosen), copy.UpdatedAt, copy.Failures > 0)
                : new FilterListState(list, IsOn(list, chosen), null, false));
            var custom = chosen.CustomLists.Select(list => {
                copies.TryGetValue(NameOf(list), out var copy);
                return new CustomFilterListState(list, copy?.Title ?? HostOf(list.Url), copy?.UpdatedAt, copy?.Failures > 0,
                    copy?.TooLarge == true);
            });
            return new(chosen.Level, customized, [.. catalog], [.. custom], chosen.CustomFilters);
        }
    }

    /// The downloads due now: each one in force whose copy is missing or due,
    /// unless one was handed out moments ago. Handing them out keeps them
    /// from being handed out again for a while.
    public IReadOnlyList<FilterDownload> Due() {
        var chosen = preferences();
        var now = clock.Now;
        lock (gate) {
            var due = new List<FilterDownload>();
            foreach (var source in Downloads(chosen)) {
                copies.TryGetValue(source.Name, out var copy);
                // Resources other than the pinned ones, as an earlier release
                // pinned, are replaced at once.
                bool stale = source == resourcesDownload && copy?.Digest is { } held && held != resourcesDigest
                    && copy.Failures == 0;
                if (copy is not null && copy.DueAt > now && !stale) continue;
                if (leases.TryGetValue(source.Name, out var leased) && now - leased < FetchLease) continue;
                leases[source.Name] = now;
                bool holdsText = copy?.Digest is not null && !stale;
                due.Add(new(source.Id, source.Url, holdsText ? copy!.EntityTag : null, holdsText ? copy!.LastModified : null));
            }
            return due;
        }
    }

    /// Makes every download in force due now, as the person asked to update
    /// the lists, so the platform downloads each again on its next ask.
    /// Answers whether any was held.
    public bool RefreshAll() {
        var chosen = preferences();
        var now = clock.Now;
        lock (gate) {
            bool any = false;
            foreach (var source in Downloads(chosen)) {
                leases.Remove(source.Name);
                if (!copies.TryGetValue(source.Name, out var copy) || copy.DueAt <= now) continue;
                copies[source.Name] = copy with { DueAt = now };
                any = true;
            }
            if (any) SaveState();
            return any;
        }
    }

    /// What `id` names among the downloads in force, or null for one the
    /// person turned off or removed since it was handed out.
    private Download? DownloadOf(Guid id) => Downloads(preferences()).FirstOrDefault(source => source.Id == id);

    /// Keeps the copy a download of `id` brought, due again when the list says
    /// it expires, and converts the lists again if its rules changed. Answers
    /// whether `id` names a download the core asked for. The caller holds no
    /// core lock: the text is hashed, counted and written here.
    public bool Fetched(Guid id, string text, string? entityTag, string? lastModified) {
        ArgumentNullException.ThrowIfNull(text);
        if (DownloadOf(id) is not { } source) return false;
        var bytes = Encoding.UTF8.GetBytes(text);
        string digest = Convert.ToHexStringLower(SHA256.HashData(bytes));
        // Resources run in pages, so only the pinned bytes are kept.
        if (source == resourcesDownload && digest != resourcesDigest) {
            Fail(source, tooLarge: false);
            return true;
        }
        var listText = new FilterListText(text);
        if (bytes.Length > MaximumListBytes || listText.RuleCount() > MaximumListRules) {
            Fail(source, tooLarge: true);
            return true;
        }
        var refresh = Refresh(listText.Expiry());
        var now = clock.Now;
        bool changed;
        lock (gate) {
            changed = !copies.TryGetValue(source.Name, out var previous) || previous.Digest != digest;
            if (changed) WriteText(source.Name, bytes, text);
            copies[source.Name] = new(digest, entityTag, lastModified, now, Next(now, refresh), refresh, 0, listText.Title());
            leases.Remove(source.Name);
            SaveState();
        }
        // The link-tracking list has no content rules to convert.
        RebuildWhenSettled(changed && source != linkTrackingDownload);
        return true;
    }

    /// The copy `id` names is still current, as its server said. Answers
    /// whether the device holds that copy.
    public bool NotModified(Guid id) {
        if (DownloadOf(id) is not { } source) return false;
        var now = clock.Now;
        lock (gate) {
            if (!copies.TryGetValue(source.Name, out var copy) || copy.Digest is null) return false;
            copies[source.Name] = copy with { UpdatedAt = now, DueAt = Next(now, copy.Refresh), Failures = 0 };
            leases.Remove(source.Name);
            SaveState();
        }
        RebuildWhenSettled(false);
        return true;
    }

    /// A download of `id` failed: the copy the device holds stays in use, and
    /// it is tried again later, each time a little later than the last.
    /// Answers whether `id` names a download the core asked for.
    public bool Failed(Guid id) {
        if (DownloadOf(id) is not { } source) return false;
        Fail(source, tooLarge: false);
        return true;
    }

    /// A download of `id` grew past the most the core keeps, and the platform
    /// stopped it: the copy the device holds stays in use, and the list shows
    /// it is too large. Answers whether `id` names a download the core asked for.
    public bool TooLarge(Guid id) {
        if (DownloadOf(id) is not { } source) return false;
        Fail(source, tooLarge: true);
        return true;
    }

    /// Keeps the copy the device holds after a download of `source` brought
    /// nothing it can use, too large or not at all, and tries again later.
    private void Fail(Download source, bool tooLarge) {
        var now = clock.Now;
        lock (gate) {
            var copy = copies.GetValueOrDefault(source.Name) ?? new(null, null, null, null, now, UsualRefresh, 0);
            int failures = copy.Failures + 1;
            var retry = TimeSpan.FromTicks(Math.Min(LongestRetry.Ticks, FirstRetry.Ticks << Math.Min(failures - 1, MostRetryDoublings)));
            copies[source.Name] = copy with { DueAt = now + retry, Failures = failures, TooLarge = tooLarge || copy.TooLarge };
            leases.Remove(source.Name);
            SaveState();
        }
        RebuildWhenSettled(false);
    }

    /// The person turned a list on or off, added or removed one, or changed
    /// their own filters. A list they removed goes with its copy.
    public void SubscriptionsChanged() {
        var kept = preferences().CustomLists.Select(NameOf).ToHashSet();
        lock (gate) {
            foreach (var gone in copies.Keys.Where(name => name.StartsWith("custom-", StringComparison.Ordinal) && !kept.Contains(name)).ToList()) {
                copies.Remove(gone);
                leases.Remove(gone);
                heldTexts.Remove(gone);
                if (folder is not null && !closed) File.Delete(Path.Combine(folder, "lists", gone + ".txt"));
            }
            SaveState();
        }
        Rebuild();
    }

    /// Converts the lists again once no download handed out moments ago is
    /// still to report, so a batch of downloads converts them once; `changed`
    /// says this report changed a list.
    private void RebuildWhenSettled(bool changed) {
        var now = clock.Now;
        lock (gate) {
            rebuildDeferred |= changed;
            // The link-tracking list feeds no rules, so a download of it in
            // flight holds no rebuild back.
            if (!rebuildDeferred || leases.Any(lease => lease.Key != LinkTrackingName && now - lease.Value < FetchLease)) return;
            rebuildDeferred = false;
        }
        Rebuild();
    }

    /// How long a copy stays current: what the list says, within the bounds
    /// that keep updates neither stale nor a burden on its maintainers.
    private static TimeSpan Refresh(TimeSpan? expiry) {
        var refresh = expiry ?? UsualRefresh;
        return refresh < ShortestRefresh ? ShortestRefresh : refresh > LongestRefresh ? LongestRefresh : refresh;
    }

    /// When a copy brought up to date `now` is due, spread over
    /// `RefreshSpread` of its refresh.
    private static DateTimeOffset Next(DateTimeOffset now, TimeSpan refresh) =>
        now + refresh + TimeSpan.FromTicks((long)(refresh.Ticks * RefreshSpread * Random.Shared.NextDouble()));

    #endregion

    #region Actions - Link tracking

    /// The `$removeparam` filters of the link-tracking list's latest copy,
    /// read once per copy, or null before one arrived. The first ask after a
    /// copy arrives reads it holding no lock.
    public ParameterFilterList? LinkTrackingFilters() {
        string digest;
        lock (gate) {
            if (copies.GetValueOrDefault(LinkTrackingName)?.Digest is not { } held) return null;
            if (linkTracking is { } read && read.Digest == held) return read.Filters;
            digest = held;
        }
        if (ReadText(LinkTrackingName) is not { } text) return null;
        var filters = ParameterFilterList.Read(new FilterListText(text).Resolved(engineConditions));
        // A copy that arrived meanwhile is read on the next ask.
        lock (gate) linkTracking = (digest, filters);
        return filters;
    }

    #endregion

    #region Actions - Lifetime

    /// Starts no worker from now on, waits for every one still converting,
    /// compiling or announcing so they keep and announce what they made, and
    /// then closes: a download reported or a list changed afterwards writes
    /// nothing, so once this returns no worker runs and nothing writes in the
    /// folder. A worker that failed stays unreported, as it was while the
    /// library ran.
    public void Stop() {
        Task[] running;
        lock (gate) {
            stopped = true;
            running = [.. workers];
        }
        Task.WhenAll(running).ConfigureAwait(ConfigureAwaitOptions.SuppressThrowing).GetAwaiter().GetResult();
        lock (gate) closed = true;
    }

    /// Runs `work` on a worker that `Stop` waits for, forgetting those that
    /// finished. The caller holds the lock.
    private void StartWorker(Action work) {
        workers.RemoveAll(worker => worker.IsCompleted);
        workers.Add(Task.Run(work));
    }

    #endregion
}
