using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    // Transient presentations do not survive process restart. Keep their terminal
    // receipts with the authority so a late dismiss cannot archive a promoted page.
    private readonly HashSet<Guid> completedTransients = [];

    #endregion

    #region Actions - Transient

    internal void RequirePendingTransient(Guid? id) {
        if (id is { } value && completedTransients.Contains(value))
            throw new BrowserRuleException(BrowserRuleCodes.TransientAlreadyCompleted);
    }

    private NativeSessionCommand PrepareTransientCommand(ulong expected, JsonObject request) {
        var args = request["arguments"]!.AsObject();
        var completion = Id(args["requestId"]);
        RequirePendingTransient(completion);
        var spaceId = Id(request["spaceId"]); var profileId = Id(request["profileId"]);
        _ = TransferSpace(spaceId, profileId);
        var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
        bool adopt = false;
        if (operation == SessionOperation.TransientPromote) {
            var sourceSpace = Id(args["sourceSpaceId"]); var sourceProfile = Id(args["sourceProfileId"]);
            _ = TransferSpace(sourceSpace, sourceProfile);
            TransientProfile? lease = args["leaseSpaceId"] is null ? null
                : new(Id(args["leaseSpaceId"]), Id(args["leaseProfileId"]));
            adopt = TransientPagePolicy.CanAdopt(new(sourceSpace, sourceProfile), lease,
                new(spaceId, profileId), args["sourceAccessible"]!.GetValue<bool>(),
                args["destinationAccessible"]!.GetValue<bool>(), args["supportsLiveAdoption"]!.GetValue<bool>());
        } else if (operation != SessionOperation.TransientArchive) throw new BrowserRuleException(BrowserRuleCodes.UnknownTransientCommand);
        var (next, answer) = EditSpace(request, operation == SessionOperation.TransientPromote
            ? SessionOperation.TabPromoteTransient : SessionOperation.TabArchiveTransient);
        answer["adoptLivePage"] = adopt && args["tab"] is not null;
        return new(this, expected, next, Output(answer), transientCompletion: completion);
    }

    #endregion
}
