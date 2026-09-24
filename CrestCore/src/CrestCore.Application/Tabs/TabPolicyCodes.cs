using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the page-residency, process-recovery, tab-dismissal and
/// tab-selection policy operations. They match the native lifecycle models'
/// case names.
internal static class TabPolicyCodes {
    #region Actions - Encoding

    public static string Recovery(ProcessRecoveryAction action) => action == ProcessRecoveryAction.Reload ? "reload" : "showFailure";

    public static string Dismissal(TabDismissalAction action) => action switch {
        TabDismissalAction.UnloadPage => "unloadPage",
        TabDismissalAction.CloseTab => "closeTab",
        _ => "closeWindow"
    };

    public static JsonObject ReleaseLimitAnswer(int limit) => new() { ["limit"] = limit };

    public static JsonObject ReleasePlanAnswer(IReadOnlyList<string> offScreen, IReadOnlyList<string> presentedFallback) => new() {
        ["tabIDs"] = Identifiers(offScreen),
        ["fallbackTabIDs"] = Identifiers(presentedFallback)
    };

    public static JsonObject RecoveryAnswer(ProcessRecoveryAction action) => new() {
        ["action"] = Recovery(action),
        ["maximumAutomaticReloads"] = PageProcessRecoveryPolicy.MaximumAutomaticReloads
    };

    public static JsonObject DismissalAnswer(TabDismissalAction action) => new() { ["action"] = Dismissal(action) };

    public static JsonObject SelectionFallbackAnswer(int? index) => new() { ["index"] = index };

    private static JsonArray Identifiers(IReadOnlyList<string> values) =>
        new(values.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray());

    #endregion
}
