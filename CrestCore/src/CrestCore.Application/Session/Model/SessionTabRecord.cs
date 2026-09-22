using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// <summary>A domain tab together with fields owned by the persisted Swift record.</summary>
internal sealed class SessionTabRecord {
    #region Variables

    private readonly JsonObject original;

    #endregion

    #region Constructors

    public SessionTabRecord(JsonObject? original = null) => this.original = (JsonObject?)original?.DeepClone() ?? new();

    #endregion

    #region Actions - Decoding

    public TabState Decode() {
        var id = LegacySessionDocument.Id(original["id"]);
        var nativeKind = original["nativeContent"] is JsonObject native ? LegacySessionDocument.Text(native["kind"]) : null;
        var url = nativeKind is null ? LegacySessionDocument.Text(original["url"]) : null;
        var storedTitle = LegacySessionDocument.Text(original["title"]);
        var content = TabContent.FromStored(nativeKind, url, storedTitle ?? "");
        return new(id, content, url, storedTitle ?? content.Title(url),
            LegacySessionDocument.Placement(original["placement"]), LegacySessionDocument.OptionalId(original["folderID"]),
            LegacySessionDocument.Text(original["savedURL"]), LegacySessionDocument.Text(original["customTitle"]),
            LegacySessionDocument.Date(original["lastActivatedAt"]), LegacySessionDocument.OptionalDate(original["positionModifiedAt"]),
            LegacySessionDocument.OptionalDate(original["titleModifiedAt"]),
            original["keepsPageLoaded"]?.GetValue<bool>() ?? false, LegacySessionDocument.OptionalId(original["splitGroupID"]));
    }

    #endregion

    #region Actions - Encoding

    public JsonObject Encode() => (JsonObject)original.DeepClone();

    public JsonObject Encode(TabState tab) {
        var value = (JsonObject)original.DeepClone();
        value["id"] = LegacySessionDocument.SwiftId(tab.Id);
        value["title"] = tab.Title;
        value["url"] = tab.Url;
        value["placement"] = TabPlacementCodes.Name(tab.Placement);
        value["folderID"] = LegacySessionDocument.SwiftId(tab.FolderId);
        value["savedURL"] = tab.SavedUrl;
        value["customTitle"] = tab.CustomTitle;
        LegacySessionDocument.WriteDate(value, "lastActivatedAt", tab.LastActivatedAt);
        LegacySessionDocument.WriteDate(value, "positionModifiedAt", tab.PositionModifiedAt, editTimestamp: true);
        LegacySessionDocument.WriteDate(value, "titleModifiedAt", tab.TitleModifiedAt, editTimestamp: true);
        value["keepsPageLoaded"] = tab.KeepsPageLoaded;
        value["splitGroupID"] = LegacySessionDocument.SwiftId(tab.SplitGroupId);
        value["symbol"] ??= tab.Content.Symbol;
        if (tab.Content.NativeKind is { } nativeKind) {
            var native = value["nativeContent"] as JsonObject ?? new();
            native["kind"] = nativeKind;
            if (native.Parent is null) value["nativeContent"] = native;
        } else value.Remove("nativeContent");
        return value;
    }

    #endregion

    #region Actions - Records

    public SessionTabRecord Copy() => new(original);

    #endregion

    #region Mutators

    public JsonNode? Metadata(string field) => original[field];

    public bool SetMetadata(string field, JsonNode? value) {
        if (JsonNode.DeepEquals(original[field], value)) return false;
        original[field] = value?.DeepClone();
        return true;
    }

    #endregion
}
