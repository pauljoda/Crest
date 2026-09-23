using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the window policy operations. They match the native
/// window-state projection's case names.
internal static class WindowCodes {
    #region Variables

    public const string Window = "window";
    public const string First = "first";
    public const string None = "none";

    #endregion

    #region Actions - Encoding

    public static string Selection(WindowTabSelection selection) => selection switch {
        WindowTabSelection.Window => Window,
        WindowTabSelection.First => First,
        _ => None
    };

    public static JsonObject RepairAnswer(WindowRepair repair) => new() {
        ["selectedSpaceID"] = repair.SelectedSpaceId.ToString("D"),
        ["selections"] = new JsonArray(repair.Selections.Select(value => (JsonNode?)Selection(value)).ToArray()),
        ["splitLayouts"] = Ids(repair.SplitLayouts),
        ["capturedSpaceIDs"] = repair.CapturedSpaceIds is { } captured ? Ids(captured) : null
    };

    public static JsonObject SplitLayoutAnswer(IReadOnlyList<double>? fractions) => new() {
        ["fractions"] = fractions is null ? null : new JsonArray(fractions.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray())
    };

    public static JsonObject TearOffAnswer(bool allowed) => new() { ["allowed"] = allowed };

    private static JsonArray Ids(IEnumerable<Guid> values) =>
        new(values.Select(value => (JsonNode?)value.ToString("D")).ToArray());

    #endregion
}
