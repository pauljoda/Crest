using System.Security.Cryptography;
using System.Text;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// WebKit content rule conversion and caching for `FilterLibrary`.
internal sealed partial class FilterLibrary {
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
    /// once from what an earlier conversion stored, or on a worker. A stopped
    /// library converts nothing.
    private void RebuildRules() {
        var chosen = preferences();
        string key;
        List<(string Name, string Digest)> inputs;
        ContentRuleListSet? restored = null;
        lock (gate) {
            if (stopped) return;
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
                StartWorker(() => Build(key, inputs, chosen.CustomFilters));
            }
        }
        if (restored is not null) announce(new ContentRuleListsChanged(restored));
    }

    /// The lists in force that the device holds a copy of, with their digests,
    /// and the person's own filters. The caller holds the lock.
    private List<(string Name, string Digest)> Inputs(FilterPreferences chosen) {
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
            string? own = null;
            foreach (var (name, _) in inputs) {
                if (TextOf(name, customFilters) is not { } text) continue;
                var resolved = new FilterListText(text).Resolved(conditions);
                texts.Add(resolved);
                if (name == CustomFiltersName) own = resolved;
            }
            var rules = ContentFilter.ContentRulesFor(texts);
            // The lists' hiding goes through the cosmetic bridge on every
            // engine: the generic rules as elements appear, and the sites' own
            // from its first answer. In the lists, a site's hiding rule matches
            // every address and is weighed on every load the page makes. The
            // person's own hiding, which Block Element writes, stays here: few
            // rules, which WebKit applies before a page first renders and in a
            // sheet the page can neither reach nor outrank.
            var ownHiding = own is null ? [] : ContentFilter.ContentRulesFor([own]).Rules.Where(Hides);
            rules = rules with { Rules = [.. rules.Rules.Where(rule => !Hides(rule)).Concat(ownHiding)] };
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

    /// Whether a converted rule hides elements rather than blocking a load.
    private static bool Hides(string rule) => rule.Contains("\"css-display-none\"", StringComparison.Ordinal);

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
}
