using System.Text.Json.Nodes;

namespace CrestCore.Application;

/// <summary>A Space snapshot with named record collections for application rules.</summary>
internal sealed record SpaceDocument(JsonObject Metadata, SpaceSections Sections) {
    #region Variables

    internal IReadOnlyList<JsonNode> Tabs => Sections.Tabs;
    internal IReadOnlyList<JsonNode> Folders => Sections.Folders;
    internal IReadOnlyList<JsonNode> History => Sections.History;
    internal IReadOnlyList<JsonNode> ArchivedTabs => Sections.ArchivedTabs;

    #endregion

    #region Constructors

    internal SpaceDocument(JsonObject metadata, IReadOnlyDictionary<string, IReadOnlyList<JsonNode>> sections)
        : this(metadata, new SpaceSections(sections["tabs"], sections["folders"], sections["history"], sections["archivedTabs"])) { }

    #endregion
}
