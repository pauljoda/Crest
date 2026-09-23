using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// <summary>A decoded native edit, its compact Space snapshot and the tab the
/// requesting window shows in that Space, if any.</summary>
internal sealed record SessionEditRequest(SessionOperation Operation, JsonObject Space, SessionEditArguments Arguments,
    DateTimeOffset Now, double ReferenceSeconds, Guid? ViewedTabId) {
    #region Variables

    private static readonly DateTimeOffset SwiftEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Construction

    public static SessionEditRequest Create(SessionOperation operation, JsonObject space,
        SessionEditArguments arguments, double referenceSeconds, Guid? viewedTabId)
        => new(operation, space, arguments, SwiftEpoch.AddSeconds(referenceSeconds), referenceSeconds, viewedTabId);

    #endregion

    #region Actions - Decoding

    public static SessionEditRequest Decode(ReadOnlySpan<byte> input) {
        if (input.Length > NativeSessionEditor.MaximumBytes) throw new ProtocolException(ProtocolErrorCodes.SessionEditLimit);
        var parsed = Protocol.Parse(input);
        if (parsed.GetProperty("version").GetInt32() != Protocol.Version)
            throw new ProtocolException(ProtocolErrorCodes.VersionMismatch);
        var request = JsonNode.Parse(input)!.AsObject();
        var seconds = parsed.GetProperty("now").GetDouble();
        var operation = SessionOperationCodes.Parse(Protocol.Text(parsed, "operation"));
        return Create(operation,
            (JsonObject)request["space"]!.DeepClone(), SessionEditArguments.Decode(request["arguments"]!.AsObject(), operation),
            seconds, request["viewedTabId"] is { } viewed ? NativeSessionAuthority.Id(viewed) : null);
    }

    public (LegacySessionDocument Document, WorkspaceState State) RestoreSpace() {
        var session = new JsonObject { ["spaces"] = new JsonArray(Space.DeepClone()) };
        var document = new LegacySessionDocument(new() { ["session"] = session });
        return (document, document.Read(new SystemIdSource()));
    }

    #endregion

    #region Actions - Encoding

    public byte[] Encode() => Encoding.UTF8.GetBytes(new JsonObject {
        ["version"] = Protocol.Version,
        ["operation"] = SessionOperationCodes.Name(Operation),
        ["space"] = Space.DeepClone(),
        ["arguments"] = Arguments.Encode(),
        ["now"] = ReferenceSeconds,
        ["viewedTabId"] = ViewedTabId?.ToString("D")
    }.ToJsonString());

    #endregion
}
