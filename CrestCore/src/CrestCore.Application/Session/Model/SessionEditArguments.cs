using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// <summary>Optional command fields shared across tab, split, folder, and appearance edits.</summary>
internal sealed record SessionEditArguments {
    #region Variables

    public TabState? Tab { get; init; }
    public IReadOnlyList<Guid>? Ids { get; init; }
    public IReadOnlyList<SessionTabObservation>? CopyObservations { get; init; }
    public TabIconAccent? IconAccent { get; init; }

    public Guid? TabId { get; init; }
    public Guid? FallbackTabId { get; init; }
    public Guid? FolderId { get; init; }
    public Guid? Before { get; init; }
    /// The tab a new tab opens after; the core keeps it outside that tab's split.
    public Guid? After { get; init; }
    public TabPlacement? Placement { get; init; }
    public SavedLocationAction? Action { get; init; }

    public int? Index { get; init; }
    public bool? Select { get; init; }
    public bool? Detach { get; init; }
    public bool? ReturnToSavedUrl { get; init; }
    public bool? Keep { get; init; }
    public bool? ResetArchivePlacement { get; init; }
    public bool? FaviconChanged { get; init; }
    public bool? HasFavicon { get; init; }
    public string? Title { get; init; }
    public string? Url { get; init; }
    public TabIconMode? Mode { get; init; }
    public string? Emoji { get; init; }

    public Guid RequiredTabId => TabId ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public TabPlacement RequiredPlacement => Placement ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public TabState RequiredTab => Tab ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public IReadOnlyList<Guid> RequiredIds => Ids ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);

    #endregion

    #region Actions - Decoding

    public static SessionEditArguments Decode(JsonObject value, SessionOperation operation) {
        var fields = FieldsFor(operation);
        JsonNode? Read(string key) => fields.Contains(key) ? value[key] : null;
        Guid? Id(string key) => Read(key) is { } node ? Guid.Parse(node.GetValue<string>()) : null;
        bool? Flag(string key) => Read(key)?.GetValue<bool>();
        string? Text(string key) => Read(key)?.GetValue<string>();
        IReadOnlyList<Guid>? IdList(string key) => Read(key) is JsonArray ids
            ? ids.Select(node => Guid.Parse(node!.GetValue<string>())).ToArray() : null;

        return new() {
            Tab = Read("tab") is JsonObject tab ? StoredSessionCodec.DecodeTab(tab) : null,
            Ids = IdList("ids"),
            CopyObservations = Read("copyObservations") is JsonArray observations
                ? observations.Select(node => SessionTabObservation.Decode(node!)).ToArray() : null,
            IconAccent = Read("iconAccent") is JsonObject accent ? StoredSessionCodec.DecodeIconAccent(accent) : null,
            TabId = Id("tabId"),
            FolderId = Id("folderId"),
            Before = Id("before"),
            After = Id("after"),
            Placement = Text("placement") is { } placement
                ? TabPlacement.Named(placement) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlacement) : null,
            Action = Text("action") is { } action ? SavedLocationActionCodes.Parse(action) : null,
            Index = Read("index")?.GetValue<int>(),
            Select = Flag("select"),
            Detach = Flag("detach"),
            ReturnToSavedUrl = Flag("returnToSavedURL"),
            Keep = Flag("keep"),
            ResetArchivePlacement = Flag("resetArchivePlacement"),
            FaviconChanged = Flag("faviconChanged"),
            HasFavicon = Flag("hasFavicon"),
            Title = Text("title"),
            Url = Text("url"),
            Mode = TabIconMode.Named(Text("mode")),
            Emoji = Text("emoji"),
        };
    }

    private static IReadOnlyList<string> FieldsFor(SessionOperation operation) => operation switch {
        SessionOperation.TabPromoteTransient or SessionOperation.TabArchiveTransient => ["tab"],
        SessionOperation.TabCloseDurable => ["tabId", "returnToSavedURL"],
        SessionOperation.TabOpen => ["tab", "index", "after", "select"],
        SessionOperation.TabCopy => ["tabId", "ids", "placement", "index", "select", "copyObservations"],
        SessionOperation.TabRename => ["tabId", "title"],
        SessionOperation.TabObserve => ["tabId", "url", "title", "iconAccent", "faviconChanged", "hasFavicon"],
        SessionOperation.TabIcon => ["tabId", "mode", "emoji", "iconAccent", "hasFavicon"],
        SessionOperation.TabFaviconCache => ["tabId", "url", "iconAccent", "hasFavicon"],
        SessionOperation.TabSavedLocation => ["tabId", "action"],
        SessionOperation.TabResidency => ["tabId", "keep"],
        SessionOperation.TabMove => ["tabId", "placement", "folderId", "before", "detach"],
        SessionOperation.TabClose or SessionOperation.TabDelete => ["tabId", "resetArchivePlacement"],
        SessionOperation.TabClearCurrent => ["resetArchivePlacement"],
        _ => []
    };

    #endregion
}
