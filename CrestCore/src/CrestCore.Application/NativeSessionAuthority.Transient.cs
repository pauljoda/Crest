using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority
{
    // Transient presentations do not survive process restart. Keep their terminal
    // receipts with the authority so a late dismiss cannot archive a promoted page.
    private readonly HashSet<Guid> completedTransients = [];

    internal void RequirePendingTransient(Guid? id)
    {
        if (id is { } value && completedTransients.Contains(value))
            throw new BrowserRuleException("transient_already_completed");
    }

    private NativeSessionCommand PrepareTransientCommand(ulong expected, JsonObject request)
    {
        var args = request["arguments"]!.AsObject();
        var completion = Id(args["requestId"]);
        RequirePendingTransient(completion);
        var spaceId = Id(request["spaceId"]); var profileId = Id(request["profileId"]);
        _ = TransferSpace(spaceId, profileId);
        var operation = request["operation"]!.GetValue<string>();
        bool adopt = false;
        if (operation == "transient.promote")
        {
            var sourceSpace = Id(args["sourceSpaceId"]); var sourceProfile = Id(args["sourceProfileId"]);
            _ = TransferSpace(sourceSpace, sourceProfile);
            TransientProfile? lease = args["leaseSpaceId"] is null ? null
                : new(new(Id(args["leaseSpaceId"])), new(Id(args["leaseProfileId"])));
            adopt = TransientPagePolicy.CanAdopt(new(new(sourceSpace), new(sourceProfile)), lease,
                new(new(spaceId), new(profileId)), args["sourceAccessible"]!.GetValue<bool>(),
                args["destinationAccessible"]!.GetValue<bool>(), args["supportsLiveAdoption"]!.GetValue<bool>());
        }
        else if (operation != "transient.archive") throw new BrowserRuleException("unknown_transient_command");
        var edit = request.DeepClone().AsObject();
        edit["operation"] = operation == "transient.promote" ? "tab.promote_transient" : "tab.archive_transient";
        var prepared = PrepareTabCommand(expected, edit);
        var output = JsonNode.Parse(prepared.Output)!.AsObject();
        output["adoptLivePage"] = adopt && args["tab"] is not null;
        return new(this, expected, prepared.Document, TransferOutput(output), transientCompletion: completion);
    }
}
