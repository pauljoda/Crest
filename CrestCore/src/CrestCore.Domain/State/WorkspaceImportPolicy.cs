using System.Text;

namespace CrestCore.Domain;

public static class WorkspaceImportPolicy {
    #region Variables

    public const int MaximumSpaces = 64;
    public const int MaximumPinnedTabs = 12;
    public const int MaximumFolders = 500;

    #endregion

    #region Actions - State policy

    public static void RequireSpaceCapacity(int existing, int additions) {
        if ((long)existing + additions > MaximumSpaces) throw new BrowserRuleException("space_limit_reached");
    }

    public static void RequirePinnedCapacity(int count) {
        if (count > MaximumPinnedTabs) throw new BrowserRuleException("pinned_limit_reached");
    }

    public static string FolderMatchKey(string title) => string.Concat(title.Normalize(NormalizationForm.FormKD)
        .Where(char.IsLetterOrDigit)).ToLowerInvariant();

    #endregion
}
