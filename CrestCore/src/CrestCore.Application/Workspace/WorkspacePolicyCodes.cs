using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// The `workspace.command_route` request and answer: which authority applies a
/// session command, `local`, `source` (the Space a borrowed workspace borrows
/// from) or `rejected`.
internal static class WorkspacePolicyCodes {
    #region Actions - Decoding

    public sealed record CommandRouteRequest(SessionOperation Command, bool Borrowed) {
        public static CommandRouteRequest Decode(JsonElement request) {
            Members(request, "command", "borrowed");
            var command = SessionOperationCodes.Parse(Protocol.Text(request, "command", 64));
            return new(command, Flag(request, "borrowed"));
        }
    }

    #endregion

    #region Actions - Encoding

    public static string Route(BorrowedCommandRoute route) => route switch {
        BorrowedCommandRoute.Source => "source",
        BorrowedCommandRoute.Rejected => "rejected",
        _ => "local"
    };

    public static JsonObject RouteAnswer(BorrowedCommandRoute route) => new() { ["route"] = Route(route) };

    #endregion
}
