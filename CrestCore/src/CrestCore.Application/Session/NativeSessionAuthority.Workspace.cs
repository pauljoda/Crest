using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Workspace

    private NativeSessionCommand PrepareWorkspaceCommand(ulong expected, JsonObject request) {
        if (workspaceKind != BrowserWorkspaceKind.Persistent) throw new BrowserRuleException(BrowserRuleCodes.PersistentWorkspaceRequired);
        var followUp = new WindowFollowUp(IssuingWindow(request));
        var (next, answer) = NativeWorkspaceImport.Preview(session, request["arguments"]!.AsObject(),
            request["mode"]!.GetValue<string>(), request["now"]!.GetValue<double>(), followUp);
        var output = Encoding.UTF8.GetBytes(answer.ToJsonString());
        if (output.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionSizeLimit);
        if (next is null) return new(this, expected, session, output, answer["error"]!.GetValue<string>());
        Validate(next);
        return new(this, expected, next, output, followUp: followUp);
    }

    #endregion
}
