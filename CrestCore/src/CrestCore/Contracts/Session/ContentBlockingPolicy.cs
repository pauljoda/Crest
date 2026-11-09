namespace CrestCore.Contracts;

/// How a Space blocked ads and trackers before blocking held for every Space
/// alike: Balanced or Off. Spaces still carry it, so older builds and other
/// devices read their sessions as before, but `ContentBlockingLevel` decides
/// what blocks; a device that never chose a level starts Off only if every
/// one of its Spaces was Off.
///
/// The stored session spells a policy as its `Name`, so a name never changes.
/// A policy travels as its index in `All`, so `All` is append-only.
public sealed class ContentBlockingPolicy {
    #region Variables

    public static readonly ContentBlockingPolicy Balanced = new(name: "balanced", title: "Balanced", blocksContent: true);
    public static readonly ContentBlockingPolicy Off = new(name: "off", title: "Off", blocksContent: false);

    public static IReadOnlyList<ContentBlockingPolicy> All { get; } = [Balanced, Off];

    public string Name { get; }

    /// What the settings call the policy.
    [Localized]
    public string Title { get; }

    /// The policy blocks anything at all.
    public bool BlocksContent { get; }

    #endregion

    #region Constructors

    private ContentBlockingPolicy(string name, string title, bool blocksContent) {
        Name = name;
        Title = title;
        BlocksContent = blocksContent;
    }

    #endregion

    #region Actions - Lookup

    public static ContentBlockingPolicy? Named(string? name) => All.FirstOrDefault(policy => policy.Name == name);

    #endregion
}
