using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.ShortcutPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Shortcuts

    /// Null when the operation is not a shortcut policy.
    private static JsonObject? EvaluateShortcuts(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.ShortcutsBindings => ResolveShortcuts(Requests.Bindings.Decode(request)),
        PolicyOperation.ShortcutsAssign => AssignShortcut(Requests.Assign.Decode(request)),
        PolicyOperation.ShortcutsNumberedSelection => NumberedSelections(Requests.NumberedSelection.Decode(request)),
        _ => null
    };

    private static JsonObject ResolveShortcuts(Requests.Bindings request) => ShortcutCodes.BindingsAnswer(
        ShortcutBindingPolicy.Resolve(request.Commands, request.Overrides, request.Platform));

    private static JsonObject AssignShortcut(Requests.Assign request) => ShortcutCodes.AssignmentAnswer(
        ShortcutBindingPolicy.Assign(request.Command, request.Shortcut, request.ReplacingConflicts, request.Commands,
            request.Overrides, request.Platform));

    private static JsonObject NumberedSelections(Requests.NumberedSelection request) =>
        ShortcutCodes.SelectionsAnswer(NumberedSelectionPolicy.Resolve(request.TabCount, request.SpaceCount));

    #endregion
}
