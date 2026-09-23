using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Limits

    /// Null when the operation is not `limits`: one answer for every capacity
    /// the core enforces, so native surfaces never keep their own copies of
    /// the numbers.
    private static JsonObject? EvaluateLimits(PolicyOperation operation, JsonElement request) {
        if (operation != PolicyOperation.Limits) return null;
        PolicyFields.Members(request);
        return new() {
            ["pinnedTabs"] = BrowserLimits.PinnedTabs,
            ["folders"] = BrowserLimits.Folders,
            ["folderDepth"] = BrowserLimits.FolderDepth,
            ["historyEntries"] = BrowserLimits.HistoryEntries,
            ["splitMembers"] = BrowserLimits.SplitMembers,
            ["brandColors"] = BrowserLimits.BrandColors,
            ["crestPalette"] = BrowserLimits.CrestPalette,
            ["spaces"] = BrowserLimits.Spaces,
            ["tabsPerSpace"] = BrowserLimits.TabsPerSpace,
            ["syncRecords"] = NativeSyncJournal.MaximumRecords
        };
    }

    #endregion
}
