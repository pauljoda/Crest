using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// The members of a stored Space that hold its records rather than its settings.
    private static readonly string[] SpaceRecords = [Key.Tabs, Key.Folders, Key.SplitGroups, Key.ArchivedTabs, Key.History];

    #endregion

    #region Actions - Spaces

    internal static SpaceDocument DecodeSpace(JsonNode? node) {
        var value = Object(node);
        var metadata = Fields(value, [.. SpaceRecords, LegacySelectionFields.SelectedTab]);
        return new(metadata, Items(value[Key.Tabs]).Select(DecodeTab).ToArray(),
            Items(value[Key.Folders]).Select(DecodeFolder).ToArray(),
            Items(value[Key.SplitGroups]).Select(DecodeSplitGroup).ToArray(),
            Items(value[Key.ArchivedTabs]).Select(DecodeArchivedTab).ToArray(),
            Items(value[Key.History]).Select(DecodeHistoryEntry).ToArray());
    }

    internal static JsonObject Encode(SpaceDocument space) {
        var value = space.Metadata.DeepClone().AsObject();
        value[Key.SplitGroups] = EncodeAll(space.SplitGroups, Encode);
        value[Key.Tabs] = EncodeAll(space.Tabs, Encode);
        value[Key.Folders] = EncodeAll(space.Folders, Encode);
        value[Key.ArchivedTabs] = EncodeAll(space.ArchivedTabs, Encode);
        value[Key.History] = EncodeHistory(space.History);
        return value;
    }

    internal static JsonArray EncodeHistory(IEnumerable<HistoryEntryState> history) => EncodeAll(history, Encode);

    #endregion

    #region Actions - Session

    /// A session; unlike its other members, its Spaces are never optional.
    internal static SessionDocument DecodeSession(JsonNode? node) {
        var value = Object(node);
        var spaces = value[Key.Spaces] as JsonArray ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedState);
        return new(Fields(value, [Key.Spaces, LegacySelectionFields.SelectedSpace]), spaces.Select(DecodeSpace).ToArray());
    }

    internal static JsonObject Encode(SessionDocument session) {
        var value = session.Metadata.DeepClone().AsObject();
        value[Key.Spaces] = EncodeAll(session.Spaces, Encode);
        return value;
    }

    /// A value's members other than the excluded ones.
    internal static JsonObject Fields(JsonObject value, IReadOnlyCollection<string> excluded) =>
        new(value.Where(member => !excluded.Contains(member.Key))
            .Select(member => KeyValuePair.Create(member.Key, member.Value?.DeepClone())));

    private static JsonArray EncodeAll<T>(IEnumerable<T> records, Func<T, JsonObject> encode) =>
        new(records.Select(record => (JsonNode?)encode(record)).ToArray());

    #endregion
}
