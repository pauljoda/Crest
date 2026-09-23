using System.Text;

namespace CrestCore.Domain;

public static class WorkspaceImportPolicy {
    #region Variables

    public const int MaximumSpaces = 64;
    public const int MaximumPinnedTabs = BrowserLimits.PinnedTabs;
    public const int MaximumFolders = 500;

    #endregion

    #region Actions - State policy

    public static void RequireSpaceCapacity(int existing, int additions) {
        if ((long)existing + additions > MaximumSpaces) throw new BrowserRuleException(BrowserRuleCodes.SpaceLimitReached);
    }

    public static void RequirePinnedCapacity(int count) {
        if (count > MaximumPinnedTabs) throw new BrowserRuleException(BrowserRuleCodes.PinnedLimitReached);
    }

    /// An imported Space must already hold well-formed split runs. Repair
    /// would quietly rewrite a malformed archive; the import rejects it instead.
    public static void RequireSplitMembership(IReadOnlyList<SplitMember> tabs) {
        ArgumentNullException.ThrowIfNull(tabs);
        var repaired = SplitMembershipPolicy.Repair(tabs);
        for (int index = 0; index < tabs.Count; index++)
            if (repaired[index] != tabs[index].Group) throw new BrowserRuleException(BrowserRuleCodes.InvalidSplit);
    }

    public static string FolderMatchKey(string title) => string.Concat(title.Normalize(NormalizationForm.FormKD)
        .Where(char.IsLetterOrDigit)).ToLowerInvariant();

    #endregion
}
