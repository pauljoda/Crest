using System.Text.Json.Nodes;

namespace CrestCore.Application;

/// <summary>
/// Selection fields that older session documents stored: the viewed Space on the
/// session and the selected tab on each Space. Selection is window state, so the
/// core accepts documents that still carry them, removes them on the way in and
/// never writes them. Native storage folds them once into window selection
/// records that lack their own.
/// </summary>
internal static class LegacySelectionFields {
    #region Variables

    public const string SelectedSpace = "selectedSpaceID";
    public const string SelectedTab = "selectedTabID";

    #endregion

    #region Actions - Removal

    /// Removes the session-level field from a session's metadata.
    public static JsonObject WithoutSessionSelection(JsonObject metadata) {
        metadata.Remove(SelectedSpace);
        return metadata;
    }

    /// Removes the per-Space field from a Space's metadata.
    public static JsonObject WithoutSpaceSelection(JsonObject space) {
        space.Remove(SelectedTab);
        return space;
    }

    /// Removes both from a whole session value, including its Spaces.
    public static JsonObject WithoutSelection(JsonObject session) {
        WithoutSessionSelection(session);
        foreach (var space in session["spaces"] as JsonArray ?? [])
            if (space is JsonObject value) WithoutSpaceSelection(value);
        return session;
    }

    #endregion
}
