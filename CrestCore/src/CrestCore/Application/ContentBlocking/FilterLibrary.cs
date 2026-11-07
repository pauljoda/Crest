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
/// are ready. Until a list arrives, Crest's own baseline rules block.
internal sealed class FilterLibrary {
    #region Types

    /// What the device holds of one list: its text's digest, or null before a
    /// download succeeded; the validators that download gave; when the copy was
    /// last brought up to date and when it is due again; how long the list
    /// says a copy stays current; and how many attempts in a row failed.
    private sealed record Copy(string? Digest, string? EntityTag, string? LastModified, DateTimeOffset? UpdatedAt,
        DateTimeOffset DueAt, TimeSpan Refresh, int Failures);

    #endregion

    #region Variables

    /// The longest list the core keeps, within the 16 MiB an intent may carry.
    public const int MaximumListBytes = 15 * 1024 * 1024;

    /// The most rules one compiled list holds; WebKit refuses more than 150,000.
    private const int RulesPerList = 70_000;

    /// Names the converter: change it whenever the content filter's crate
    /// changes what lists convert to, so devices convert theirs again.
    private const string RulesRevision = "adblock-0.13.5";

    private const string IdentifierPrefix = "com.pauldavis.crest.content-filter.";

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
    /// analytics hosts. They block before any list arrives, and beside them.
    private const string BaselineRules = """
        ! Title: Crest baseline
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
    private readonly IReadOnlyList<string> languages;
    private readonly Func<IReadOnlyDictionary<FilterList, bool>> choices;
    private readonly Action<Change> announce;
    private readonly IClock clock;
    private readonly Dictionary<FilterList, Copy> copies = [];
    /// Without a folder: each list's text, and each compiled list's source.
    private readonly Dictionary<FilterList, string> heldTexts = [];
    private readonly Dictionary<string, string> heldSources = [];
    private readonly Dictionary<FilterList, DateTimeOffset> leases = [];
    private ContentRuleListSet published = new([]);
    private string? publishedKey;
    /// The rules being converted, and whether the inputs changed meanwhile.
    private string? buildingKey;
    private bool rebuildWanted;
    /// A list changed while other downloads were out: the lists convert once
    /// the last of them reports.
    private bool rebuildDeferred;

    #endregion

    #region Constructors

    /// The library for a core keeping its session in `storageDirectory`, or in
    /// memory without one. `languages` decide the regional lists that are on
    /// by default; `choices` answers the person's own.
    public FilterLibrary(string? storageDirectory, DevicePlatform platform, IReadOnlyList<string>? languages,
        Func<IReadOnlyDictionary<FilterList, bool>> choices, Action<Change> announce, IClock clock) {
        ArgumentNullException.ThrowIfNull(platform);
        ArgumentNullException.ThrowIfNull(choices);
        ArgumentNullException.ThrowIfNull(announce);
        ArgumentNullException.ThrowIfNull(clock);
        folder = storageDirectory is null ? null : Path.Combine(storageDirectory, "ContentFilter");
        conditions = new HashSet<string>([.. WebKitConditions, .. platform.FilterConditions]);
        this.languages = languages ?? [];
        this.choices = choices;
        this.announce = announce;
        this.clock = clock;
        RestoreState();
    }

    #endregion

    #region Actions - Lists

    /// Whether the device subscribes to `list`.
    private bool IsOn(FilterList list, IReadOnlyDictionary<FilterList, bool> chosen) =>
        chosen.TryGetValue(list, out bool isOn) ? isOn : list.IsOnByDefault(languages);

    /// Every list as the settings show it, in `FilterList.All` order.
    public IReadOnlyList<FilterListState> States() {
        var chosen = choices();
        lock (gate)
            return [.. FilterList.All.Select(list => copies.TryGetValue(list, out var copy)
                ? new FilterListState(list, IsOn(list, chosen), copy.UpdatedAt, copy.Failures > 0)
                : new FilterListState(list, IsOn(list, chosen), null, false))];
    }

    /// The downloads due now: each list the device subscribes to whose copy is
    /// missing or due, unless one was handed out moments ago. Handing them
    /// out keeps them from being handed out again for a while.
    public IReadOnlyList<FilterListFetch> Due() {
        var chosen = choices();
        var now = clock.Now;
        lock (gate) {
            var due = new List<FilterListFetch>();
            foreach (var list in FilterList.All.Where(list => IsOn(list, chosen))) {
                copies.TryGetValue(list, out var copy);
                if (copy is not null && copy.DueAt > now) continue;
                if (leases.TryGetValue(list, out var leased) && now - leased < FetchLease) continue;
                leases[list] = now;
                bool holdsText = copy?.Digest is not null;
                due.Add(new(list, list.Source, holdsText ? copy!.EntityTag : null, holdsText ? copy!.LastModified : null));
            }
            return due;
        }
    }

    /// Keeps the copy of `list` a download brought, due again when the list
    /// says it expires, and converts the lists again if its rules changed.
    public void Fetched(FilterList list, string text, string? entityTag, string? lastModified, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(list);
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(changes);
        var bytes = Encoding.UTF8.GetBytes(text);
        if (bytes.Length > MaximumListBytes) throw new Rejected(new FilterListTooLarge(MaximumListBytes));
        string digest = Convert.ToHexStringLower(SHA256.HashData(bytes));
        var refresh = Refresh(new FilterListText(text).Expiry());
        var now = clock.Now;
        bool changed;
        lock (gate) {
            changed = !copies.TryGetValue(list, out var previous) || previous.Digest != digest;
            if (changed) WriteText(list, bytes, text);
            copies[list] = new(digest, entityTag, lastModified, now, Next(now, refresh), refresh, 0);
            leases.Remove(list);
            SaveState();
        }
        changes.Publish(new FilterListsChanged(States()));
        RebuildWhenSettled(changed);
    }

    /// The copy of `list` is still current, as its server said.
    public void NotModified(FilterList list, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(list);
        ArgumentNullException.ThrowIfNull(changes);
        var now = clock.Now;
        lock (gate) {
            if (!copies.TryGetValue(list, out var copy) || copy.Digest is null) return;
            copies[list] = copy with { UpdatedAt = now, DueAt = Next(now, copy.Refresh), Failures = 0 };
            leases.Remove(list);
            SaveState();
        }
        changes.Publish(new FilterListsChanged(States()));
        RebuildWhenSettled(false);
    }

    /// A download of `list` failed: the copy the device holds stays in use,
    /// and the list is tried again later, each time a little later than the last.
    public void Failed(FilterList list, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(list);
        ArgumentNullException.ThrowIfNull(changes);
        var now = clock.Now;
        lock (gate) {
            var copy = copies.GetValueOrDefault(list) ?? new(null, null, null, null, now, UsualRefresh, 0);
            int failures = copy.Failures + 1;
            var retry = TimeSpan.FromTicks(Math.Min(LongestRetry.Ticks, FirstRetry.Ticks << Math.Min(failures - 1, 16)));
            copies[list] = copy with { DueAt = now + retry, Failures = failures };
            leases.Remove(list);
            SaveState();
        }
        changes.Publish(new FilterListsChanged(States()));
        RebuildWhenSettled(false);
    }

    /// The person turned a list on or off.
    public void SubscriptionsChanged(ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        changes.Publish(new FilterListsChanged(States()));
        Rebuild();
    }

    /// Converts the lists again once no download handed out moments ago is
    /// still to report, so a batch of downloads converts them once; `changed`
    /// says this report changed a list.
    private void RebuildWhenSettled(bool changed) {
        var now = clock.Now;
        lock (gate) {
            rebuildDeferred |= changed;
            if (!rebuildDeferred || leases.Values.Any(leased => now - leased < FetchLease)) return;
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

    /// Converts the lists again unless their rules are the ones in force: at
    /// once from what an earlier conversion stored, or on a worker.
    private void Rebuild() {
        var chosen = choices();
        string key;
        List<(FilterList List, string Digest)> inputs;
        ContentRuleListSet? restored = null;
        lock (gate) {
            inputs = [.. FilterList.All.Where(list => IsOn(list, chosen))
                .Select(list => (List: list, Digest: copies.GetValueOrDefault(list)?.Digest))
                .Where(input => input.Digest is not null).Select(input => (input.List, input.Digest!))];
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
        else _ = Task.Run(() => Build(key, inputs));
    }

    /// Converts `inputs` and Crest's baseline into content rule lists, keeps
    /// them, and puts them in force. A failure leaves the rules in force.
    private void Build(string key, IReadOnlyList<(FilterList List, string Digest)> inputs) {
        ContentRuleListSet? built = null;
        bool again;
        try {
            var texts = new List<string> { BaselineRules };
            foreach (var (list, _) in inputs)
                if (ReadText(list) is { } text) texts.Add(new FilterListText(text).Resolved(conditions));
            var rules = ContentFilter.ContentRulesFor(texts);
            built = new([.. Split(rules).Select((source, index) => Keep(Identifier(key, index), source))]);
        } catch (Exception error) when (error is InvalidOperationException or IOException or UnauthorizedAccessException
            or DllNotFoundException or EntryPointNotFoundException) {
            // The lists keep their copies; the next change converts them again.
        } finally {
            lock (gate) {
                buildingKey = null;
                again = rebuildWanted;
                rebuildWanted = false;
                if (built is not null) {
                    Publish(key, built);
                    SaveState();
                }
            }
        }
        if (built is not null) announce(new ContentRuleListsChanged(built));
        if (again) Rebuild();
    }

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
    private string RulesKey(IReadOnlyList<(FilterList List, string Digest)> inputs) {
        var description = new StringBuilder(RulesRevision).Append('\n');
        description.AppendJoin(',', conditions.Order(StringComparer.Ordinal)).Append('\n');
        foreach (var (list, digest) in inputs) description.Append(list.Name).Append(':').Append(digest).Append('\n');
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(description.ToString())));
    }

    private static string Identifier(string key, int index) => $"{IdentifierPrefix}{key[..16]}.{index}";

    /// Puts the set converted for `key` in force. The caller holds the lock.
    private void Publish(string key, ContentRuleListSet set) {
        published = set;
        publishedKey = key;
        if (folder is null) {
            foreach (var stale in heldSources.Keys.Where(identifier => !set.Identifiers.Contains(identifier)).ToList())
                heldSources.Remove(stale);
            return;
        }
        // A rules file no set names any more is never asked for again.
        try {
            foreach (var path in Directory.EnumerateFiles(Path.Combine(folder, "rules"))) {
                string name = Path.GetFileNameWithoutExtension(path);
                if (!set.Identifiers.Contains(name) && name != key) File.Delete(path);
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

    #region Actions - Storage

    private string? ReadText(FilterList list) {
        if (folder is null) {
            lock (gate) return heldTexts.GetValueOrDefault(list);
        }
        try {
            return File.ReadAllText(Path.Combine(folder, "lists", list.Name + ".txt"));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            return null;
        }
    }

    /// Keeps a list's text. The caller holds the lock.
    private void WriteText(FilterList list, byte[] bytes, string text) {
        if (folder is null) heldTexts[list] = text;
        else WriteAtomically(Path.Combine(folder, "lists", list.Name + ".txt"), bytes);
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
        foreach (var (list, copy) in copies)
            lists[list.Name] = new JsonObject {
                ["digest"] = copy.Digest,
                ["entityTag"] = copy.EntityTag,
                ["lastModified"] = copy.LastModified,
                ["updatedAt"] = copy.UpdatedAt?.ToUnixTimeSeconds(),
                ["dueAt"] = copy.DueAt.ToUnixTimeSeconds(),
                ["refresh"] = (long)copy.Refresh.TotalSeconds,
                ["failures"] = copy.Failures
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
            if (FilterList.Named(name) is not { } list || value is not JsonObject state) continue;
            string? digest = state["digest"]?.GetValue<string>();
            if (digest is not null && !File.Exists(Path.Combine(folder, "lists", list.Name + ".txt"))) continue;
            long? updated = state["updatedAt"]?.GetValue<long>();
            copies[list] = new(digest, state["entityTag"]?.GetValue<string>(), state["lastModified"]?.GetValue<string>(),
                updated is { } seconds ? DateTimeOffset.FromUnixTimeSeconds(seconds) : null,
                DateTimeOffset.FromUnixTimeSeconds(state["dueAt"]?.GetValue<long>() ?? 0),
                TimeSpan.FromSeconds(state["refresh"]?.GetValue<long>() ?? (long)UsualRefresh.TotalSeconds),
                state["failures"]?.GetValue<int>() ?? 0);
        }
    }

    #endregion
}
