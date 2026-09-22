using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Shortcuts

    /// Null when the operation is not a shortcut policy. `commands` lists the
    /// commands this process offers, in display order; overrides are the
    /// person's persisted choices, carried through verbatim for unknown commands.
    private static JsonObject? EvaluateShortcuts(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.ShortcutsBindings: {
                    Protocol.Members(request, "version", "operation", "platform", "commands", "overrides");
                    var bindings = ShortcutBindingPolicy.Resolve(ShortcutCodes.Commands(request),
                        ShortcutCodes.Overrides(request), DeviceCodes.Platform(request));
                    return new() {
                        ["bindings"] = new JsonArray(bindings.Select(binding => (JsonNode?)new JsonObject {
                            ["command"] = binding.Command,
                            ["shortcut"] = ShortcutCodes.Chord(binding.Shortcut),
                            ["default"] = ShortcutCodes.Chord(binding.Default),
                            ["customized"] = binding.IsCustomized
                        }).ToArray())
                    };
                }
            case PolicyOperation.ShortcutsAssign: {
                    Protocol.Members(request, "version", "operation", "platform", "commands", "overrides", "command",
                        "shortcut", "replacingConflicts");
                    var assignment = ShortcutBindingPolicy.Assign(ShortcutCodes.Command(request.GetProperty("command")),
                        ShortcutCodes.OptionalChord(request.GetProperty("shortcut")),
                        request.GetProperty("replacingConflicts").GetBoolean(), ShortcutCodes.Commands(request),
                        ShortcutCodes.Overrides(request), DeviceCodes.Platform(request));
                    return new() {
                        ["result"] = ShortcutCodes.Result(assignment.Result),
                        ["conflicts"] = ShortcutCodes.Names(assignment.Conflicts),
                        ["overrides"] = assignment.Overrides is { } overrides ? ShortcutCodes.Overrides(overrides) : null
                    };
                }
            case PolicyOperation.ShortcutsNumberedSelection: {
                    Protocol.Members(request, "version", "operation", "tabCount", "spaceCount");
                    var selections = NumberedSelectionPolicy.Resolve(DeviceCodes.Count(request, "tabCount"),
                        DeviceCodes.Count(request, "spaceCount"));
                    return new() {
                        ["selections"] = new JsonArray(selections.Select(selection => (JsonNode?)new JsonObject {
                            ["command"] = selection.Command,
                            ["target"] = ShortcutCodes.Target(selection.Target),
                            ["index"] = selection.Index
                        }).ToArray())
                    };
                }
            default:
                return null;
        }
    }

    #endregion
}
