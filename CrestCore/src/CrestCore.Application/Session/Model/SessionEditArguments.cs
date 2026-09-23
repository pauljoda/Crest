using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// <summary>Optional command fields shared across tab, split, folder, and appearance edits.</summary>
internal sealed record SessionEditArguments {
    #region Variables

    private JsonObject? original;

    public SessionTabRecord? Tab { get; init; }
    public IReadOnlyList<Guid>? Ids { get; init; }
    public IReadOnlyList<Guid>? TabIds { get; init; }
    public IReadOnlyList<SessionTabObservation>? CopyObservations { get; init; }
    public JsonNode? IconAccent { get; init; }
    public JsonObject? Color { get; init; }
    public JsonObject? FolderColorValue { get; init; }

    public Guid? TabId { get; init; }
    public Guid? TargetId { get; init; }
    public Guid? FallbackTabId { get; init; }
    public Guid? FolderId { get; init; }
    public Guid? ParentId { get; init; }
    public Guid? BeforeFolderId { get; init; }
    public Guid? Before { get; init; }
    /// The tab a new tab opens after; the core keeps it outside that tab's split.
    public Guid? After { get; init; }
    public Guid? GroupId { get; init; }
    public TabPlacement? Placement { get; init; }
    public SavedLocationAction? Action { get; init; }

    public int? Index { get; init; }
    public int? Offset { get; init; }
    public double? Lifetime { get; init; }
    public bool? Select { get; init; }
    public bool? Detach { get; init; }
    public bool? ReturnToSavedUrl { get; init; }
    public bool? Keep { get; init; }
    public bool? Collapsed { get; init; }
    public bool? ResetArchivePlacement { get; init; }
    public bool? FaviconChanged { get; init; }
    public bool? HasFavicon { get; init; }
    public string? Title { get; init; }
    public string? Url { get; init; }
    public TabIconMode? Mode { get; init; }
    public string? Emoji { get; init; }
    public string? Symbol { get; init; }
    public string? FolderSymbolValue { get; init; }

    public Guid RequiredTabId => TabId ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public Guid RequiredTargetId => TargetId ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public Guid RequiredFolderId => FolderId ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public Guid RequiredGroupId => GroupId ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public TabPlacement RequiredPlacement => Placement ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public SessionTabRecord RequiredTab => Tab ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public IReadOnlyList<Guid> RequiredIds => Ids ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
    public IReadOnlyList<Guid> RequiredTabIds => TabIds ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);

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
            original = (JsonObject)value.DeepClone(),
            Tab = Read("tab") is JsonObject tab ? new(tab) : null,
            Ids = IdList("ids"),
            TabIds = IdList("tabIds"),
            CopyObservations = Read("copyObservations") is JsonArray observations
                ? observations.Select(node => SessionTabObservation.Decode(node!)).ToArray() : null,
            IconAccent = Read("iconAccent")?.DeepClone(),
            Color = Read("color") is JsonObject color ? (JsonObject)color.DeepClone() : null,
            FolderColorValue = operation == SessionOperation.FolderColor && Read("value") is JsonObject folderColor
                ? (JsonObject)folderColor.DeepClone() : null,
            TabId = Id("tabId"),
            TargetId = Id("targetId"),
            FallbackTabId = Id("fallbackTabId"),
            FolderId = Id("folderId"),
            ParentId = Id("parentId"),
            BeforeFolderId = Id("beforeFolderId"),
            Before = Id("before"),
            After = Id("after"),
            GroupId = Id("groupId"),
            Placement = Text("placement") is { } placement ? Enum.Parse<TabPlacement>(placement, true) : null,
            Action = Text("action") is { } action ? SavedLocationActionCodes.Parse(action) : null,
            Index = Read("index")?.GetValue<int>(),
            Offset = Read("offset")?.GetValue<int>(),
            Lifetime = Read("lifetime")?.GetValue<double>(),
            Select = Flag("select"),
            Detach = Flag("detach"),
            ReturnToSavedUrl = Flag("returnToSavedURL"),
            Keep = Flag("keep"),
            Collapsed = Flag("collapsed"),
            ResetArchivePlacement = Flag("resetArchivePlacement"),
            FaviconChanged = Flag("faviconChanged"),
            HasFavicon = Flag("hasFavicon"),
            Title = Text("title"),
            Url = Text("url"),
            Mode = Text("mode") is { } mode ? TabIconModeCodes.Parse(mode) : null,
            Emoji = Text("emoji"),
            Symbol = Text("symbol"),
            FolderSymbolValue = operation == SessionOperation.FolderSymbol ? Text("value") : null
        };
    }

    private static IReadOnlyList<string> FieldsFor(SessionOperation operation) => operation switch {
        SessionOperation.TabPromoteTransient or SessionOperation.TabArchiveTransient or SessionOperation.TabRestoreArchive => ["tab"],
        SessionOperation.TabCloseDurable => ["tabId", "fallbackTabId", "returnToSavedURL"],
        SessionOperation.TabCleanup => ["lifetime", "tabIds"],
        SessionOperation.TabOpen => ["tab", "index", "after", "select"],
        SessionOperation.TabTouch => ["tabId"],
        SessionOperation.TabCopy => ["tabId", "ids", "placement", "index", "select", "copyObservations"],
        SessionOperation.TabRename => ["tabId", "title"],
        SessionOperation.TabObserve => ["tabId", "url", "title", "iconAccent", "faviconChanged", "hasFavicon"],
        SessionOperation.TabIcon => ["tabId", "mode", "emoji", "iconAccent", "hasFavicon"],
        SessionOperation.TabFaviconCache => ["tabId", "url", "iconAccent", "hasFavicon"],
        SessionOperation.TabSavedLocation => ["tabId", "action"],
        SessionOperation.TabResidency => ["tabId", "keep"],
        SessionOperation.TabMove => ["tabId", "placement", "folderId", "before", "detach"],
        SessionOperation.SplitOpenLink => ["tab", "targetId", "index", "ids", "copyObservations"],
        SessionOperation.SplitJoin => ["tabId", "targetId", "index", "ids", "copyObservations"],
        SessionOperation.SplitJoinInPlace => ["tabId", "targetId", "index", "groupId"],
        SessionOperation.SplitLeave => ["tabId"],
        SessionOperation.SplitReorder => ["tabId", "index", "offset"],
        SessionOperation.SplitDissolve => ["groupId"],
        SessionOperation.SplitMove => ["groupId", "placement", "folderId", "before"],
        SessionOperation.FolderCreate => ["folderId", "title", "placement", "parentId", "color", "symbol", "tabIds", "detach"],
        SessionOperation.FolderColor or SessionOperation.FolderSymbol => ["folderId", "value"],
        SessionOperation.FolderRename => ["folderId", "title"],
        SessionOperation.FolderCollapse => ["folderId", "collapsed"],
        SessionOperation.FolderDelete => ["folderId"],
        SessionOperation.FolderMove => ["folderId", "placement", "parentId", "beforeFolderId", "before"],
        SessionOperation.TabsFile => ["tabIds", "placement", "folderId", "before", "beforeFolderId", "detach"],
        SessionOperation.TabClose or SessionOperation.TabDelete => ["tabId", "fallbackTabId", "resetArchivePlacement"],
        SessionOperation.TabClearCurrent => ["fallbackTabId", "resetArchivePlacement"],
        _ => []
    };

    #endregion

    #region Actions - Encoding

    public JsonObject Encode() {
        var value = (JsonObject?)original?.DeepClone() ?? new();
        void PutId(string key, Guid? id) { if (id is { } present) value[key] = present.ToString("D"); }
        void PutFlag(string key, bool? flag) { if (flag is { } present) value[key] = present; }
        void PutText(string key, string? text) { if (text is not null) value[key] = text; }
        if (Tab is not null) value["tab"] = Tab.Encode();
        if (Ids is not null) value["ids"] = new JsonArray(Ids.Select(id => (JsonNode?)JsonValue.Create(id.ToString("D"))).ToArray());
        if (TabIds is not null) value["tabIds"] = new JsonArray(TabIds.Select(id => (JsonNode?)JsonValue.Create(id.ToString("D"))).ToArray());
        if (CopyObservations is not null) value["copyObservations"] = new JsonArray(CopyObservations.Select(item => (JsonNode)item.Encode()).ToArray());
        if (IconAccent is not null) value["iconAccent"] = IconAccent.DeepClone();
        if (Color is not null) value["color"] = Color.DeepClone();
        if (FolderColorValue is not null) value["value"] = FolderColorValue.DeepClone();
        if (FolderSymbolValue is not null) value["value"] = FolderSymbolValue;
        PutId("tabId", TabId); PutId("targetId", TargetId); PutId("fallbackTabId", FallbackTabId);
        PutId("folderId", FolderId); PutId("parentId", ParentId); PutId("beforeFolderId", BeforeFolderId);
        PutId("before", Before); PutId("after", After); PutId("groupId", GroupId);
        if (Placement is { } placement) value["placement"] = TabPlacementCodes.Name(placement);
        if (Action is { } action) value["action"] = SavedLocationActionCodes.Name(action);
        if (Mode is { } mode) value["mode"] = TabIconModeCodes.Name(mode);
        if (Index is { } index) value["index"] = index;
        if (Offset is { } offset) value["offset"] = offset;
        if (Lifetime is { } lifetime) value["lifetime"] = lifetime;
        PutFlag("select", Select); PutFlag("detach", Detach); PutFlag("returnToSavedURL", ReturnToSavedUrl);
        PutFlag("keep", Keep); PutFlag("collapsed", Collapsed); PutFlag("resetArchivePlacement", ResetArchivePlacement);
        PutFlag("faviconChanged", FaviconChanged); PutFlag("hasFavicon", HasFavicon);
        PutText("title", Title); PutText("url", Url); PutText("emoji", Emoji); PutText("symbol", Symbol);
        return value;
    }

    #endregion
}
