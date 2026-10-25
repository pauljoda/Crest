namespace CrestCore.Contracts;

/// A Space's native ad/tracker protection. Stored names and wire order remain
/// stable; the bundled native snapshot is shared without sharing browsing data.
public sealed class ContentBlockingPolicy {
    #region Static Variables

    public static readonly ContentBlockingPolicy Balanced = new(name: "balanced", title: "Balanced",
        switchTitle: "Turn Off Content Blocking in This Space", ruleList: ReadBundledRules());
    public static readonly ContentBlockingPolicy Off = new(name: "off", title: "Off",
        switchTitle: "Turn On Balanced Content Blocking in This Space", ruleList: null);
    public static IReadOnlyList<ContentBlockingPolicy> All { get; } = [Balanced, Off];

    #endregion

    #region Variables

    private readonly ContentRuleList? ruleList;
    public string Name { get; }
    [Localized]
    public string Title { get; }
    [Localized]
    public string SwitchTitle { get; }
    public string? Identifier => ruleList?.Identifier;
    public bool BlocksContent => ruleList is not null;

    #endregion

    #region Constructors

    private ContentBlockingPolicy(string name, string title, string switchTitle, ContentRuleList? ruleList) {
        Name = name;
        Title = title;
        SwitchTitle = switchTitle;
        this.ruleList = ruleList;
    }

    #endregion

    #region Actions - Lookup

    public static ContentBlockingPolicy? Named(string? name) => All.FirstOrDefault(policy => policy.Name == name);

    #endregion

    #region Actions - Rules

    public ContentRuleList? RuleList() => ruleList;

    private static ContentRuleList ReadBundledRules() {
        using var stream = typeof(ContentBlockingPolicy).Assembly.GetManifestResourceStream("CrestCore.ContentBlockingRules")
            ?? throw new InvalidOperationException("The bundled content-blocking snapshot is missing.");
        using var archive = new MemoryStream();
        stream.CopyTo(archive);
        return ContentRuleList.FromArchive(archive.ToArray());
    }

    #endregion
}
