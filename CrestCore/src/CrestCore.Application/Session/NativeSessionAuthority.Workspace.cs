using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Workspace

    private NativeSessionCommand PrepareWorkspaceCommand(JsonObject request) {
        if (workspaceKind != WorkspaceKind.Persistent) throw new BrowserRuleException(BrowserRuleCodes.PersistentWorkspaceRequired);
        var followUp = new WindowFollowUp(IssuingWindow(request));
        var (next, answer) = NativeWorkspaceImport.Preview(session, request["arguments"]!.AsObject(),
            request["mode"]!.GetValue<string>(), request["now"]!.GetValue<double>(), followUp);
        var output = Encoding.UTF8.GetBytes(answer.ToJsonString());
        if (output.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionSizeLimit);
        if (next is null) return new(this, session, session, output, answer["error"]!.GetValue<string>());
        Validate(next);
        return new(this, session, next, output, followUp: followUp);
    }

    #endregion
}
