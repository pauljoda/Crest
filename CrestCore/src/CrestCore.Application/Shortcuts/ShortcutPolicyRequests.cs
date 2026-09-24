using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the shortcut policy operations. `commands` lists the
/// commands this process offers, in display order; overrides are the person's
/// persisted choices, carried through verbatim for unknown commands.
internal static class ShortcutPolicyRequests {
    #region Actions - Decoding

    public sealed record Bindings(IReadOnlyList<string> Commands, IReadOnlyDictionary<string, ShortcutChord?> Overrides,
        DevicePlatform Platform) {
        public static Bindings Decode(JsonElement request) {
            Members(request, "platform", "commands", "overrides");
            var commands = ShortcutCodes.Commands(request);
            var overrides = ShortcutCodes.Overrides(request);
            return new(commands, overrides, DeviceCodes.Platform(request));
        }
    }

    public sealed record Assign(string Command, ShortcutChord? Shortcut, bool ReplacingConflicts, IReadOnlyList<string> Commands,
        IReadOnlyDictionary<string, ShortcutChord?> Overrides, DevicePlatform Platform) {
        public static Assign Decode(JsonElement request) {
            Members(request, "platform", "commands", "overrides", "command", "shortcut", "replacingConflicts");
            var command = ShortcutCodes.Command(Element(request, "command"));
            var shortcut = ShortcutCodes.OptionalChord(Element(request, "shortcut"));
            bool replacing = Flag(request, "replacingConflicts");
            var commands = ShortcutCodes.Commands(request);
            var overrides = ShortcutCodes.Overrides(request);
            return new(command, shortcut, replacing, commands, overrides, DeviceCodes.Platform(request));
        }
    }

    public sealed record NumberedSelection(int TabCount, int SpaceCount) {
        public static NumberedSelection Decode(JsonElement request) {
            Members(request, "tabCount", "spaceCount");
            int tabs = DeviceCodes.Count(request, "tabCount");
            return new(tabs, DeviceCodes.Count(request, "spaceCount"));
        }
    }

    #endregion
}
