namespace CrestCore.Contracts;

/// How a Space blocks ads and trackers. Balanced applies the filter lists the
/// device subscribes to, except on the sites the Space turned blocking off for;
/// Off blocks nothing.
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
