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
internal sealed class FilterLibrary {
    #region Types

    /// What the device holds of one download: its text's digest, or null
    /// before a download succeeded; the validators that download gave; when the
    /// copy was last brought up to date and when it is due again; how long the
    /// list says a copy stays current; how many attempts in a row failed; and,
    /// for a list, what it calls itself.
    private sealed record Copy(string? Digest, string? EntityTag, string? LastModified, DateTimeOffset? UpdatedAt,
        DateTimeOffset DueAt, TimeSpan Refresh, int Failures, string? Title = null, bool TooLarge = false);

    /// One thing the library downloads: a catalog list or one the person
    /// added, named on the device by `Name` and on the wire by `Id`.
    private sealed record Download(string Name, Guid Id, string Url);

    #endregion

    #region Variables

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
    private const string RulesRevision = "adblock-0.13.5+css-validation;site-hiding-only;trusted-chosen";

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
        "https://github.com/pauljoda/Crest/releases/download/" + ResourcesRelease + "/ublock-resources.json";

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
    /// How long a download the core handed out keeps the list from being
    /// handed out again.
    private static readonly TimeSpan FetchLease = TimeSpan.FromMinutes(10);

    /// The `!#if` tokens that hold in WebKit's content rules: Safari's, and
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
    private readonly Func<Device.FilterPreferences> preferences;
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

    #endregion

    #region Constructors

    /// The library for a core keeping its session in `storageDirectory`, or in
    /// memory without one. `languages` decide the regional lists that are on
    /// by default; `preferences` answers the person's own choices, the lists
    /// they added and their own filters. Tests may name resources of their own
    /// with their digest, `resourcesDigest`.
    public FilterLibrary(string? storageDirectory, DevicePlatform platform, IReadOnlyList<string>? languages,
        Func<Device.FilterPreferences> preferences, Action<Change> announce, IClock clock, string? resourcesUrl = null,
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
    private bool IsOn(FilterList list, Device.FilterPreferences chosen) =>
        chosen.Choices.TryGetValue(list, out bool isOn) ? isOn : list.IsOnByDefault(chosen.Level, languages);

    /// How a catalog list is named on the wire: the same on every device.
    internal static Guid IdOf(FilterList list) =>
        new(SHA256.HashData(Encoding.UTF8.GetBytes("crest.filter-list:" + list.Name)).AsSpan(0, 16));

    /// How a list the person added is named on the device.
    private static string NameOf(CustomFilterList list) => "custom-" + list.Id.ToString("N");

    private static string HostOf(string url) => Uri.TryCreate(url, UriKind.Absolute, out var address) ? address.Host : url;

    private static string Digest(string text) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(text)));

    /// The lists the device subscribes to: the catalog's, then the person's.
    private IEnumerable<Download> Lists(Device.FilterPreferences chosen) =>
        FilterList.All.Where(list => IsOn(list, chosen)).Select(list => new Download(list.Name, IdOf(list), list.Source))
            .Concat(chosen.CustomLists.Where(list => list.IsOn).Select(list => new Download(NameOf(list), list.Id, list.Url)));

    /// Every download in force: the lists the device subscribes to, the
    /// resources, and the link-tracking list while the device cleans copied
    /// links.
    private IEnumerable<Download> Downloads(Device.FilterPreferences chosen) {
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
            var retry = TimeSpan.FromTicks(Math.Min(LongestRetry.Ticks, FirstRetry.Ticks << Math.Min(failures - 1, 16)));
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
                if (folder is not null) File.Delete(Path.Combine(folder, "lists", gone + ".txt"));
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

    /// When a copy brought up to date `now` is due, spread over a tenth of
    /// its refresh so devices do not all ask at once.
    private static DateTimeOffset Next(DateTimeOffset now, TimeSpan refresh) =>
        now + refresh + TimeSpan.FromTicks((long)(refresh.Ticks * 0.1 * Random.Shared.NextDouble()));

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

    #region Actions - Content rules

    /// The content rule lists a page that blocks applies now. The first call
    /// finds the rules a previous launch converted, or starts converting.
    public ContentRuleListSet Rules() {
        lock (gate) if (publishedKey is not null) return published;
        Rebuild();
        lock (gate) return published;
    }

    /// The source of the compiled list `identifier`, which the current or a
    /// recent set names. Throws `Rejected` for one the core no longer holds.
    public ContentRuleList Source(string identifier) {
        ArgumentNullException.ThrowIfNull(identifier);
        lock (gate) {
            if (folder is null)
                return heldSources.TryGetValue(identifier, out var held)
                    ? new(identifier, held) : throw new Rejected(new ContentRuleListUnavailable(identifier));
        }
        string path = RulesPath(identifier);
        try {
            return new(identifier, File.ReadAllText(path));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            throw new Rejected(new ContentRuleListUnavailable(identifier));
        }
    }

    /// Brings every output up to date with the lists: the content rules, and
    /// the compiled filter.
    private void Rebuild() {
        RebuildRules();
        RebuildEngine();
    }

    /// Converts the lists again unless their rules are the ones in force: at
    /// once from what an earlier conversion stored, or on a worker.
    private void RebuildRules() {
        var chosen = preferences();
        string key;
        List<(string Name, string Digest)> inputs;
        ContentRuleListSet? restored = null;
        lock (gate) {
            inputs = Inputs(chosen);
            key = RulesKey(inputs);
            if (key == publishedKey) return;
            if (StoredRules(key) is { } stored) {
                Publish(key, stored);
                restored = stored;
            } else if (buildingKey is not null) {
                rebuildWanted = true;
                return;
            } else {
                buildingKey = key;
            }
        }
        if (restored is not null) announce(new ContentRuleListsChanged(restored));
        else _ = Task.Run(() => Build(key, inputs, chosen.CustomFilters));
    }

    /// The lists in force that the device holds a copy of, with their digests,
    /// and the person's own filters. The caller holds the lock.
    private List<(string Name, string Digest)> Inputs(Device.FilterPreferences chosen) {
        var inputs = Lists(chosen).Select(source => (source.Name, Digest: copies.GetValueOrDefault(source.Name)?.Digest))
            .Where(input => input.Digest is not null).Select(input => (input.Name, input.Digest!)).ToList();
        if (chosen.CustomFilters.Length > 0) inputs.Add((CustomFiltersName, Digest(chosen.CustomFilters)));
        return inputs;
    }

    /// The text of the input `name`: a list's copy, or the person's own filters.
    private string? TextOf(string name, string customFilters) => name == CustomFiltersName ? customFilters : ReadText(name);

    /// Converts `inputs` and Crest's baseline into content rule lists, keeps
    /// them, and puts them in force. A failure leaves the rules in force.
    private void Build(string key, IReadOnlyList<(string Name, string Digest)> inputs, string customFilters) {
        ContentRuleListSet? built = null;
        bool again;
        try {
            var texts = new List<string> { BaselineRules };
            foreach (var (name, _) in inputs)
                if (TextOf(name, customFilters) is { } text) texts.Add(new FilterListText(text).Resolved(conditions));
            var rules = ContentFilter.ContentRulesFor(texts);
            // Generic hiding goes through the cosmetic bridge, as elements
            // appear, on every engine; the site's own hiding stays here.
            rules = rules with { Rules = [.. rules.Rules.Where(rule => !HidesGenerically(rule))] };
            built = new([.. Split(rules).Select((source, index) => Keep(Identifier(key, index), source))]);
        } catch (Exception error) when (error is InvalidOperationException or IOException or UnauthorizedAccessException
            or DllNotFoundException or EntryPointNotFoundException) {
            // The lists keep their copies; the next change converts them again.
        } finally {
            var chosen = preferences();
            lock (gate) {
                buildingKey = null;
                again = rebuildWanted;
                rebuildWanted = false;
                // Rules for lists no longer wanted are not put in force; the
                // wanted ones are converted, or restored, next.
                if (built is not null && key == RulesKey(Inputs(chosen))) {
                    Publish(key, built);
                    SaveState();
                } else if (built is not null) {
                    built = null;
                    again = true;
                }
            }
        }
        if (built is not null) announce(new ContentRuleListsChanged(built));
        if (again) RebuildRules();
    }

    /// Whether a converted rule hides elements on every site: a hiding rule
    /// with no site it is limited to.
    private static bool HidesGenerically(string rule) =>
        rule.Contains("\"css-display-none\"", StringComparison.Ordinal) && !rule.Contains("\"if-domain\"", StringComparison.Ordinal);

    /// The compiled lists for `rules`: as many rules as fit beside every
    /// exception, the exceptions after them in each list, since an exception
    /// reaches only the rules before it in its own list.
    private static IEnumerable<string> Split(ContentFilter.ContentRules rules) {
        int room = RulesPerList - rules.Exceptions.Count;
        if (room <= 0) throw new InvalidOperationException("The lists hold more exceptions than one compiled list can.");
        string exceptions = string.Join(',', rules.Exceptions);
        for (int start = 0; start < rules.Rules.Count; start += room) {
            var source = new StringBuilder("[");
            source.AppendJoin(',', rules.Rules.Skip(start).Take(room));
            if (exceptions.Length > 0) source.Append(',').Append(exceptions);
            yield return source.Append(']').ToString();
        }
    }

    /// The key of the rules `inputs` convert to on this platform: it changes
    /// with any list's text, with the converter and with the conditions.
    private string RulesKey(IReadOnlyList<(string Name, string Digest)> inputs) {
        var description = new StringBuilder(RulesRevision).Append(':').Append(BaselineDigest).Append('\n');
        description.AppendJoin(',', conditions.Order(StringComparer.Ordinal)).Append('\n');
        foreach (var (name, digest) in inputs) description.Append(name).Append(':').Append(digest).Append('\n');
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(description.ToString())));
    }

    private static string Identifier(string key, int index) => $"{IdentifierPrefix}{key[..16]}.{index}";

    /// Puts the set converted for `key` in force. The caller holds the lock.
    private void Publish(string key, ContentRuleListSet set) {
        if (publishedKey is not null && publishedKey != key) previous = (publishedKey, published);
        published = set;
        publishedKey = key;
        if (folder is null) {
            foreach (var stale in heldSources.Keys.Where(identifier => !set.Identifiers.Contains(identifier)).ToList())
                heldSources.Remove(stale);
            return;
        }
        // A rules file neither this set nor the one before it names is never
        // asked for again. The one before stays, so switching back, as
        // between Balanced and Strict, restores it at once.
        try {
            foreach (var path in Directory.EnumerateFiles(Path.Combine(folder, "rules"))) {
                string name = Path.GetFileNameWithoutExtension(path);
                bool named = set.Identifiers.Contains(name) || name == key
                    || (previous is { } before && (before.Set.Identifiers.Contains(name) || name == before.Key));
                if (!named) File.Delete(path);
            }
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            // Stale files are left for the next set to remove.
        }
    }

    /// The set an earlier conversion stored for `key`, when every list of it
    /// is still there. The caller holds the lock.
    private ContentRuleListSet? StoredRules(string key) {
        if (folder is null || !File.Exists(Path.Combine(folder, "rules", key + ".count"))) return null;
        if (!int.TryParse(File.ReadAllText(Path.Combine(folder, "rules", key + ".count")), out int count)) return null;
        var identifiers = Enumerable.Range(0, count).Select(index => Identifier(key, index)).ToList();
        return identifiers.All(identifier => File.Exists(RulesPath(identifier))) ? new(identifiers) : null;
    }

    /// Keeps a compiled list's source and answers its identifier.
    private string Keep(string identifier, string source) {
        if (folder is null) {
            lock (gate) heldSources[identifier] = source;
            return identifier;
        }
        WriteAtomically(RulesPath(identifier), Encoding.UTF8.GetBytes(source));
        return identifier;
    }

    private string RulesPath(string identifier) => Path.Combine(folder!, "rules", identifier + ".json");

    #endregion

    #region Actions - Engine filter

    /// The address of the slot an engine that checks each request itself
    /// checks against with `crest_content_filter_slot_check`. The first ask
    /// makes it, with the compiled filter in it; the slot lives as long as the
    /// core.
    public nint SlotAddress() {
        lock (gate) {
            if (slot is null) {
                slot = new ContentFilterSlot();
                // The filter compiled before an engine asked goes in at once.
                slot.Install(engine);
            }
        }
        RebuildEngine();
        lock (gate) return slot.Address;
    }

    /// What a document at `url` hides beyond what its engine blocks: on the
    /// `first` ask, the site's hiding rules and procedural filters; on every
    /// ask, the generic rules for the `classes` and `ids` it shows, one rule
    /// per selector so a selector the engine cannot read costs only itself, and
    /// the `resources` the filter blocks, whose elements collapse. Nothing
    /// before the filter is compiled.
    public CosmeticFilters Cosmetics(string url, bool first, IReadOnlyList<string> classes, IReadOnlyList<string> ids,
        IReadOnlyList<PageResource> resources) {
        ArgumentNullException.ThrowIfNull(url);
        return Reading(current => CosmeticsWith(current, url, first, classes, ids, resources));
    }

    private static CosmeticFilters CosmeticsWith(ContentFilter? current, string url, bool first, IReadOnlyList<string> classes,
        IReadOnlyList<string> ids, IReadOnlyList<PageResource> resources) {
        if (current is null) return new(true, "", [], []);
        var page = current.ResourcesFor(url);
        IEnumerable<string> site = first ? page.HideSelectors : [];
        var generic = page.GenericHide || classes.Count + ids.Count == 0 ? [] : current.HiddenSelectors(classes, ids, page.Exceptions);
        var style = new StringBuilder();
        foreach (var selector in site.Concat(generic).Distinct())
            style.Append(selector).Append("{display:none!important}\n");
        var collapse = resources.Where(resource => current.Blocks(new ContentFilter.Request(resource.Url, url, KindOf(resource.Kind))))
            .Select(resource => resource.Url).Distinct();
        return new(true, style.ToString(), first ? page.ProceduralActions : [], [.. collapse]);
    }

    /// The scriptlets the filter runs in a page's own world at `url`, before
    /// the page's scripts, as one script; empty for none, or before the filter
    /// is compiled. uBlock's scriptlets share state through a
    /// `scriptletGlobals` object their runner declares, so the script declares
    /// it too, in a function of its own that keeps their names off the page.
    public string Scriptlets(string url) {
        ArgumentNullException.ThrowIfNull(url);
        var script = Reading(current => current?.ResourcesFor(url).InjectedScript ?? "");
        return script.Length == 0 ? "" : $"(function () {{\nconst scriptletGlobals = {{}};\n{script}\n}})();\n";
    }

    /// What `use` answers from the engine in force, which a rebuild that
    /// replaces it meanwhile frees only after `use` is done.
    private T Reading<T>(Func<ContentFilter?, T> use) {
        ContentFilter? current;
        lock (gate) {
            current = engine;
            engineReaders++;
        }
        try {
            return use(current);
        } finally {
            lock (gate) {
                if (--engineReaders == 0) {
                    foreach (var retired in retiredEngines) retired.Dispose();
                    retiredEngines.Clear();
                }
            }
        }
    }

    /// What the filter calls the load of an element of `kind`.
    private static ContentFilter.RequestKind KindOf(PageResourceKind kind) => kind switch {
        PageResourceKind.Frame => ContentFilter.RequestKind.Subdocument,
        PageResourceKind.Image => ContentFilter.RequestKind.Image,
        _ => ContentFilter.RequestKind.Object,
    };

    /// Compiles the engine filter again unless the one in force matches the
    /// lists: at once from what an earlier compile saved, or on a worker.
    private void RebuildEngine() {
        var chosen = preferences();
        string key;
        List<(string Name, string Digest)> inputs;
        lock (gate) {
            inputs = Inputs(chosen);
            if (copies.GetValueOrDefault(ResourcesName)?.Digest is { } resources && resources == resourcesDigest)
                inputs.Add((ResourcesName, resources));
            key = EngineKey(inputs);
            if (key == engineKey) return;
            if (buildingEngineKey is not null) {
                engineRebuildWanted = true;
                return;
            }
            buildingEngineKey = key;
        }
        _ = Task.Run(() => BuildEngine(key, inputs, chosen.CustomFilters));
    }

    /// The key the lists in force compile to, with the pinned resources and
    /// without them.
    private (string Key, string WithoutResources) WantedEngineKey(Device.FilterPreferences chosen) {
        lock (gate) {
            var inputs = Inputs(chosen);
            string without = EngineKey(inputs);
            if (copies.GetValueOrDefault(ResourcesName)?.Digest is { } resources && resources == resourcesDigest)
                inputs.Add((ResourcesName, resources));
            return (EngineKey(inputs), without);
        }
    }

    private void BuildEngine(string key, IReadOnlyList<(string Name, string Digest)> inputs, string customFilters) {
        ContentFilter? built = null;
        bool again;
        try {
            bool wantsResources = inputs.Any(input => input.Name == ResourcesName);
            string? resources = wantsResources ? ReadText(ResourcesName) : null;
            // What the folder holds must still be the pinned bytes. Without
            // them the filter is kept under a key that does not name them, so
            // it compiles again once they arrive.
            if (resources is not null && Digest(resources) != resourcesDigest) resources = null;
            if (wantsResources && resources is null) {
                inputs = [.. inputs.Where(input => input.Name != ResourcesName)];
                key = EngineKey(inputs);
            }
            built = SavedEngine(key, resources);
            if (built is null) {
                // Crest's own baseline and the catalog's lists may run the
                // scriptlets uBlock keeps for trusted lists; the lists the
                // person added and their own filters may not.
                var chosen = new List<string> { BaselineRules };
                var added = new List<string>();
                foreach (var (name, _) in inputs.Where(input => input.Name != ResourcesName))
                    if (TextOf(name, customFilters) is { } text)
                        (FilterList.Named(name) is not null ? chosen : added).Add(new FilterListText(text).Resolved(engineConditions));
                built = ContentFilter.Compile(chosen, added, resources);
                SaveEngine(key, built);
            }
        } catch (Exception error) when (error is InvalidOperationException or IOException or UnauthorizedAccessException
            or DllNotFoundException or EntryPointNotFoundException) {
            built?.Dispose();
            built = null;
        } finally {
            var wanted = WantedEngineKey(preferences());
            lock (gate) {
                buildingEngineKey = null;
                again = engineRebuildWanted;
                engineRebuildWanted = false;
                // A filter for lists no longer wanted is not put in force.
                if (built is not null && (key == wanted.Key || key == wanted.WithoutResources)) {
                    slot?.Install(built);
                    if (engine is not null) {
                        if (engineReaders == 0) engine.Dispose();
                        else retiredEngines.Add(engine);
                    }
                    engine = built;
                    engineKey = key;
                } else {
                    built?.Dispose();
                    again |= built is not null;
                }
            }
        }
        if (again) RebuildEngine();
    }

    /// The key of the engine filter `inputs` compile to: it changes with any
    /// list's text, with the engine and with the conditions.
    private string EngineKey(IReadOnlyList<(string Name, string Digest)> inputs) {
        var description = new StringBuilder("engine:").Append(RulesRevision).Append(':').Append(BaselineDigest).Append('\n');
        description.AppendJoin(',', engineConditions.Order(StringComparer.Ordinal)).Append('\n');
        foreach (var (name, digest) in inputs) description.Append(name).Append(':').Append(digest).Append('\n');
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(description.ToString())));
    }

    /// The engine filter an earlier compile saved for `key`, with `resources`,
    /// or null. A filter this library cannot read, such as one a previous
    /// version saved, is compiled again.
    private ContentFilter? SavedEngine(string key, string? resources) {
        if (folder is null) return null;
        string path = Path.Combine(folder, "engine", key[..16] + ".dat");
        return File.Exists(path) ? ContentFilter.Load(File.ReadAllBytes(path), resources) : null;
    }

    /// Saves the engine filter for `key`, the only one kept.
    private void SaveEngine(string key, ContentFilter filter) {
        if (folder is null) return;
        string directory = Path.Combine(folder, "engine");
        WriteAtomically(Path.Combine(directory, key[..16] + ".dat"), filter.Save());
        foreach (var stale in Directory.EnumerateFiles(directory, "*.dat"))
            if (Path.GetFileNameWithoutExtension(stale) != key[..16]) File.Delete(stale);
    }

    #endregion

    #region Actions - Storage

    private string? ReadText(string name) {
        if (folder is null) {
            lock (gate) return heldTexts.GetValueOrDefault(name);
        }
        try {
            return File.ReadAllText(Path.Combine(folder, "lists", name + ".txt"));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            return null;
        }
    }

    /// Keeps a download's text. The caller holds the lock.
    private void WriteText(string name, byte[] bytes, string text) {
        if (folder is null) heldTexts[name] = text;
        else WriteAtomically(Path.Combine(folder, "lists", name + ".txt"), bytes);
    }

    private static void WriteAtomically(string path, byte[] bytes) {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string pending = path + ".pending";
        File.WriteAllBytes(pending, bytes);
        File.Move(pending, path, overwrite: true);
    }

    /// Writes every copy's state, and the rules in force. The caller holds the lock.
    private void SaveState() {
        if (folder is null) return;
        var lists = new JsonObject();
        foreach (var (name, copy) in copies)
            lists[name] = new JsonObject {
                ["digest"] = copy.Digest,
                ["entityTag"] = copy.EntityTag,
                ["lastModified"] = copy.LastModified,
                ["updatedAt"] = copy.UpdatedAt?.ToUnixTimeSeconds(),
                ["dueAt"] = copy.DueAt.ToUnixTimeSeconds(),
                ["refresh"] = (long)copy.Refresh.TotalSeconds,
                ["failures"] = copy.Failures,
                ["title"] = copy.Title,
                ["tooLarge"] = copy.TooLarge
            };
        try {
            WriteAtomically(Path.Combine(folder, "state.json"), Encoding.UTF8.GetBytes(new JsonObject { ["lists"] = lists }.ToJsonString()));
            if (publishedKey is not null)
                WriteAtomically(Path.Combine(folder, "rules", publishedKey + ".count"),
                    Encoding.UTF8.GetBytes(published.Identifiers.Count.ToString(System.Globalization.CultureInfo.InvariantCulture)));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            // The copies stay in memory; the next save writes them.
        }
    }

    /// Reads what a previous launch kept. A copy whose text is gone, or a
    /// state that does not read, starts the list over.
    private void RestoreState() {
        if (folder is null) return;
        JsonObject? lists;
        try {
            lists = JsonNode.Parse(File.ReadAllText(Path.Combine(folder, "state.json")))?["lists"] as JsonObject;
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException) {
            return;
        }
        foreach (var (name, value) in lists ?? []) {
            bool known = FilterList.Named(name) is not null || name == ResourcesName || name == LinkTrackingName
                || name.StartsWith("custom-", StringComparison.Ordinal);
            if (!known || value is not JsonObject state) continue;
            string? digest = state["digest"]?.GetValue<string>();
            if (digest is not null && !File.Exists(Path.Combine(folder, "lists", name + ".txt"))) continue;
            long? updated = state["updatedAt"]?.GetValue<long>();
            copies[name] = new(digest, state["entityTag"]?.GetValue<string>(), state["lastModified"]?.GetValue<string>(),
                updated is { } seconds ? DateTimeOffset.FromUnixTimeSeconds(seconds) : null,
                DateTimeOffset.FromUnixTimeSeconds(state["dueAt"]?.GetValue<long>() ?? 0),
                TimeSpan.FromSeconds(state["refresh"]?.GetValue<long>() ?? (long)UsualRefresh.TotalSeconds),
                state["failures"]?.GetValue<int>() ?? 0, state["title"]?.GetValue<string>(),
                state["tooLarge"]?.GetValue<bool>() ?? false);
        }
    }

    #endregion
}
