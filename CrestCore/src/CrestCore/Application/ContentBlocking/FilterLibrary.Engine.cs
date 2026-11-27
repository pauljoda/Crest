using System.Security.Cryptography;
using System.Text;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Native engine content filter compilation, cosmetic queries, and scriptlets
/// for `FilterLibrary`.
internal sealed partial class FilterLibrary {
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
        var collapse = resources.Where(resource => current.Blocks(new ContentFilter.Request(resource.Url, url, resource.Kind.RequestKind)))
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

    /// Compiles the engine filter again unless the one in force matches the
    /// lists: at once from what an earlier compile saved, or on a worker. A
    /// stopped library compiles nothing.
    private void RebuildEngine() {
        var chosen = preferences();
        string key;
        List<(string Name, string Digest)> inputs;
        lock (gate) {
            if (stopped) return;
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
            StartWorker(() => BuildEngine(key, inputs, chosen.CustomFilters));
        }
    }

    /// The key the lists in force compile to, with the pinned resources and
    /// without them.
    private (string Key, string WithoutResources) WantedEngineKey(FilterPreferences chosen) {
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
}
