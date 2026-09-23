using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Workspace

    private NativeSessionCommand PrepareWorkspaceCommand(ulong expected, JsonObject request) {
        if (workspaceKind != BrowserWorkspaceKind.Persistent) throw new BrowserRuleException(BrowserRuleCodes.PersistentWorkspaceRequired);
        var result = NativeWorkspaceImport.Preview(StoredSessionCodec.Encode(document), request["arguments"]!.AsObject(),
            request["mode"]!.GetValue<string>(), request["now"]!.GetValue<double>());
        var output = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (output.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionSizeLimit);
        if (result["error"] is { } error) return new(this, expected, document, output, error.GetValue<string>());
        var next = StoredSessionCodec.DecodeSession(result["session"]);
        Validate(next);
        return new(this, expected, next, output);
    }

    #endregion
}
