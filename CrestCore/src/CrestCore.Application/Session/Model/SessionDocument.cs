using System.Text.Json.Nodes;

namespace CrestCore.Application;

/// <summary>A published session snapshot and its ordered Spaces.</summary>
internal sealed record SessionDocument(JsonObject Metadata, IReadOnlyList<SpaceDocument> Spaces);
