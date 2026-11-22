using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using K = CrestCore.Application.StoredSessionCodec.Key;

namespace CrestCore.Application;

/// Additive fields in an accepted wire record belong to that record. A local
/// projection replaces fields this client understands and carries the rest
/// forward. Removed known fields and removed collection members stay removed.
internal static class NativeSyncCompatibility {
    #region Variables

    private sealed record Shape(string Names, Dictionary<string, Shape>? Children = null, Shape? Element = null, bool ById = false) {
        #region Constructors

        public Shape(IEnumerable<string> names, Dictionary<string, Shape>? children = null) : this(string.Join(' ', names), children) {
        }

        #endregion

        #region Variables

        public HashSet<string> Fields { get; } = Names.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.Ordinal);

        #endregion
    }

    private static readonly Shape Identity = new([K.RawValue]);
    private static readonly Shape Color = new([K.Red, K.Green, K.Blue, K.Alpha]);
    private static readonly Shape Charge = new([K.Kind, K.Value, K.Style]);
    private static readonly Shape Gradient = new([K.Colors, K.Kind, K.Angle], new() { [K.Colors] = List(Color) });

    private static readonly Shape Crest = new(
        [K.Backplate, K.FieldDivision, K.Ordinary, K.Trim, K.Symbol, K.ChargeLayout, K.BackplateColorIndex, K.SecondaryFieldColorIndex, K.OrdinaryColorIndex, K.TrimColorIndex, K.SymbolColorIndex, K.EdgeColorIndex, K.Palette, K.Charge, K.Finish, K.ChargeWeight, K.StartingPresetId, K.ShowsOutline, K.Depth, K.PaletteGradients, .. CrestMeasure.All.Select(measure => measure.Name)],
        new() { [K.Palette] = List(Color), [K.Charge] = Charge, [K.PaletteGradients] = List(Gradient) });

    private static readonly Shape Branding = new(
        [K.Colors, K.BannerPattern, K.BannerStrength, K.ReadabilityFade, K.KeepsControlsReadable, K.ThemeMode, K.GradientAngle, K.ShowsTexture, K.TextureStrength, K.IconStyle, K.SymbolColor, K.Crest, K.RenderingVersion, K.FolderColorIntensity, K.TextColorMode, K.HasCustomAppearance, K.GradientKind, K.SymbolGradient, K.ColorGradients],
        new() {
            [K.Colors] = List(Color),
            [K.SymbolColor] = Color,
            [K.Crest] = Crest,
            [K.SymbolGradient] = Gradient,
            [K.ColorGradients] = List(Gradient)
        });

    private static readonly Shape SearchProvider = new([K.Id, K.Name, K.SearchUrlTemplate, K.SuggestionUrlTemplate]);

    private static readonly Shape Browsing = new(
        [K.LegacySearchProvider, K.SelectedSearchProviderId, K.CustomSearchProviders, K.SearchSuggestionsEnabled, K.SearchFollowsDefault, K.SuggestionsFollowDefault, K.CurrentTabCleanupPolicy, K.ContentBlockingPolicy, K.DataRetention],
        new() { [K.CustomSearchProviders] = List(SearchProvider, true), [K.DataRetention] = new([K.History, K.Archive, K.Downloads]) });

    private static readonly Shape Group = new(SplitGroupPayload.Members,
        new() { [K.Id] = Identity, [K.Tint] = Color });

    private static readonly Shape Tab = new(TabPayload.Members, new() {
        [K.Id] = Identity,
        [K.SpaceId] = Identity,
        [K.FolderId] = Identity,
        [K.SplitGroupId] = Identity
    });

    private static readonly Dictionary<string, Shape> Values = new() {
        [SyncRecordKind.Space.Name] = new(SpacePayload.Members, new() {
            [K.Id] = Identity,
            [K.PrimarySpaceId] = Identity,
            [K.Branding] = Branding,
            [K.BrowsingPreferences] = Browsing,
            [K.SplitGroups] = List(Group, true)
        }),
        [SyncRecordKind.Folder.Name] = new(FolderPayload.Members, new() {
            [K.Id] = Identity,
            [K.SpaceId] = Identity,
            [K.ParentId] = Identity,
            [K.OrderAnchorTabId] = Identity,
            [K.Color] = Color
        }),
        [SyncRecordKind.Tab.Name] = Tab,
        [SyncRecordKind.History.Name] = new(HistoryPayload.Members, new() { [K.SpaceId] = Identity }),
        [SyncRecordKind.Archive.Name] = new(ArchivePayload.Members, new() { [K.Tab] = Tab })
    };

    #endregion

    #region Actions - Sync

    private static Shape List(Shape element, bool byId = false) => new("", Element: element, ById: byId);

    internal static JsonObject Preserve(JsonObject current, JsonObject? previous) {
        string kind = current[SyncPayload.Key.Type]!.GetValue<string>();
        if (previous?[SyncPayload.Key.Type]?.GetValue<string>() != kind) return current;
        return Merge(new([SyncPayload.Key.Type, SyncPayload.Key.Value], new() { [SyncPayload.Key.Value] = Values[kind] }), current, previous)
            .AsObject();
    }

    private static string? MemberId(JsonNode? value) {
        var id = value?[K.Id];
        if (id is JsonObject wrapper) id = wrapper[K.RawValue];
        return id is JsonValue raw && raw.TryGetValue<string>(out var text) ? text.ToLowerInvariant() : null;
    }

    private static JsonNode Merge(Shape shape, JsonNode current, JsonNode? previous) {
        if (current is JsonObject fields && previous is JsonObject old) {
            var result = fields.DeepClone().AsObject();
            foreach (var (key, value) in old)
                if (!shape.Fields.Contains(key) && !fields.ContainsKey(key)) result[key] = value?.DeepClone();
            if (shape.Children is not null)
                foreach (var (key, child) in shape.Children)
                    if (fields[key] is { } value) result[key] = Merge(child, value, old[key]);
            return result;
        }
        if (current is JsonArray items && previous is JsonArray oldItems && shape.Element is { } element) {
            Dictionary<string, JsonNode?>? byId = shape.ById ? oldItems.Where(n => MemberId(n) is not null)
                .GroupBy(n => MemberId(n)!).ToDictionary(g => g.Key, g => g.Last(), StringComparer.Ordinal) : null;
            return new JsonArray(items.Select((item, index) => item is null ? null : Merge(element, item,
                byId is not null ? (MemberId(item) is { } id ? byId.GetValueOrDefault(id) : null)
                    : index < oldItems.Count ? oldItems[index] : null)).ToArray());
        }
        return current.DeepClone();
    }

    #endregion
}
