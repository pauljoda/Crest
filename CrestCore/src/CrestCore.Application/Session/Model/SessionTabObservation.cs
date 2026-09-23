using System.Text.Json.Nodes;

namespace CrestCore.Application;

internal sealed record SessionTabObservation(Guid TabId, string? Url, string? Title) {
    #region Actions - Decoding

    public static SessionTabObservation Decode(JsonNode value) => new(
        Guid.Parse(value["tabId"]!.GetValue<string>()), value["url"]?.GetValue<string>(), value["title"]?.GetValue<string>());

    #endregion
}
