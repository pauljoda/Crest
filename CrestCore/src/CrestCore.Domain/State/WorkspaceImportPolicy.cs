using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

public static class WorkspaceImportPolicy {
    #region Variables

    public const int MaximumSpaces = 64;
    public const int MaximumFolders = 500;

    /// The saved folder that receives imported pinned tabs past the limit.
    public const string OverflowFolderTitle = "Imported Pinned Tabs";
    public const string OverflowFolderSymbol = "pin.slash";

    #endregion

    #region Actions - State policy

    /// Throws `Rejected` with `SpaceLimitReached` when `additions` more Spaces
    /// would take a workspace holding `existing` past the limit.
    public static void RequireSpaceCapacity(int existing, int additions) {
        if ((long)existing + additions > MaximumSpaces) throw new Rejected(new SpaceLimitReached(MaximumSpaces));
    }

    /// Throws `Rejected` with `PinnedTabsFull` when a Space cannot pin `count` tabs.
    public static void RequirePinnedCapacity(int count) {
        if (!TabPlacement.Pinned.Holds(count)) throw new Rejected(new PinnedTabsFull(TabPlacement.PinnedCapacity));
    }

    /// An imported Space must already hold well-formed split runs. Repair
    /// would quietly rewrite a malformed archive; the import is refused
    /// instead, with `InvalidImport`.
    public static void RequireSplitMembership(IReadOnlyList<SplitMember> tabs) {
        ArgumentNullException.ThrowIfNull(tabs);
        var repaired = SplitMembershipPolicy.Repair(tabs);
        for (int index = 0; index < tabs.Count; index++)
            if (repaired[index] != tabs[index].Group) throw new Rejected(new InvalidImport(ImportFlaw.MalformedSplit));
    }

    public static string FolderMatchKey(string title) => string.Concat(title.Normalize(NormalizationForm.FormKD)
        .Where(char.IsLetterOrDigit)).ToLowerInvariant();

    #endregion
}
