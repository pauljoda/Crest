using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the shortcut policy operations. A chord travels in the
/// native value's shape, `{"key":{"character":"n"},"modifiers":1}` or
/// `{"key":{"special":"leftArrow"},"modifiers":5}`; overrides map a command to
/// a chord, or to null when it was left unassigned.
internal static class ShortcutCodes {
    #region Variables

    public const int MaximumCommandLength = 64;

    #endregion

    #region Actions - Decoding

    public static IReadOnlyList<string> Commands(JsonElement request) {
        var value = request.GetProperty("commands");
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > ShortcutBindingPolicy.MaximumCommands)
            throw new BrowserRuleException(BrowserRuleCodes.ShortcutCommandLimit);
        return value.EnumerateArray().Select(Command).ToArray();
    }

    public static IReadOnlyDictionary<string, ShortcutChord?> Overrides(JsonElement request) {
        var value = request.GetProperty("overrides");
        if (value.ValueKind != JsonValueKind.Object) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
        var overrides = new Dictionary<string, ShortcutChord?>(StringComparer.Ordinal);
        foreach (var member in value.EnumerateObject()) {
            if (overrides.Count >= ShortcutBindingPolicy.MaximumOverrides)
                throw new BrowserRuleException(BrowserRuleCodes.ShortcutCommandLimit);
            if (member.Name.Length is 0 or > MaximumCommandLength) throw new ProtocolException(ProtocolErrorCodes.InvalidString);
            overrides[member.Name] = OptionalChord(member.Value);
        }
        return overrides;
    }

    public static string Command(JsonElement value) {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { Length: > 0 and <= MaximumCommandLength } command)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return command;
    }

    public static ShortcutChord? OptionalChord(JsonElement value) {
        if (value.ValueKind == JsonValueKind.Null) return null;
        Protocol.Members(value, "key", "modifiers");
        var key = value.GetProperty("key");
        int modifiers = DeviceCodes.Count(value, "modifiers");
        if (key.TryGetProperty("character", out _)) {
            Protocol.Members(key, "character");
            return ShortcutChord.Character(Protocol.Text(key, "character", ShortcutChord.MaximumCharacterLength), modifiers);
        }
        Protocol.Members(key, "special");
        return ShortcutChord.Special(Protocol.Text(key, "special", 32), modifiers);
    }

    #endregion

    #region Actions - Encoding

    public static JsonNode? Chord(ShortcutChord? chord) => chord is null ? null : new JsonObject {
        ["key"] = new JsonObject { [chord.IsSpecial ? "special" : "character"] = chord.Key },
        ["modifiers"] = chord.Modifiers
    };

    public static JsonObject Overrides(IReadOnlyDictionary<string, ShortcutChord?> overrides) {
        var value = new JsonObject();
        foreach (var (command, chord) in overrides.OrderBy(entry => entry.Key, StringComparer.Ordinal)) value[command] = Chord(chord);
        return value;
    }

    public static JsonArray Names(IEnumerable<string> commands) =>
        new(commands.Select(command => (JsonNode?)JsonValue.Create(command)).ToArray());

    public static string Result(ShortcutAssignmentResult result) => result switch {
        ShortcutAssignmentResult.Assigned => "assigned",
        ShortcutAssignmentResult.Conflict => "conflict",
        _ => "invalid"
    };

    public static JsonObject BindingsAnswer(IEnumerable<ShortcutBinding> bindings) => new() {
        ["bindings"] = new JsonArray(bindings.Select(binding => (JsonNode?)new JsonObject {
            ["command"] = binding.Command,
            ["shortcut"] = Chord(binding.Shortcut),
            ["default"] = Chord(binding.Default),
            ["customized"] = binding.IsCustomized
        }).ToArray())
    };

    /// The assignment's outcome; `overrides` is null when nothing changed.
    public static JsonObject AssignmentAnswer(ShortcutAssignment assignment) => new() {
        ["result"] = Result(assignment.Result),
        ["conflicts"] = Names(assignment.Conflicts),
        ["overrides"] = assignment.Overrides is { } overrides ? Overrides(overrides) : null
    };

    public static JsonObject SelectionsAnswer(IEnumerable<NumberedSelection> selections) => new() {
        ["selections"] = new JsonArray(selections.Select(selection => (JsonNode?)new JsonObject {
            ["command"] = selection.Command,
            ["target"] = selection.Target.Name,
            ["index"] = selection.Index
        }).ToArray())
    };

    #endregion
}
