using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a new Space starts as in each kind of workspace: its name, symbol,
/// accent and look, what it searches and keeps, and whether it offers to save
/// passwords. Every new Space has a profile of its own and one Start Page tab,
/// and opens freely. An ordinary Space takes the next accent in turn and wears
/// that accent's house look; a private one wears the private look
/// and never offers to save or sync passwords.
public sealed class SpaceTemplate {
    #region Static Variables

    /// A new Space keeps what it browses until the person chooses otherwise.
    private static readonly DataRetentionPreferences KeepsEverything = new(DataRetention.Forever, DataRetention.Forever,
        DataRetention.Forever);

    /// The one purple a private Space wears, with a plain key for its symbol.
    private static readonly SpaceBranding PrivateLook = new(new([new(0.58, 0.30, 0.76)]), SpaceBannerPattern.Solid,
        BannerStrength: 1, ReadabilityFade: 1, KeepsControlsReadable: true, SpaceThemeMode.Banner, GradientAngle: 0,
        ShowsTexture: false, SpaceIconStyle.SimpleSymbol, SymbolColor: null,
        SpaceCrest.PlainField(CrestBackplate.None, CrestSymbol.Key, CrestTrim.None, layers: [0, 0, 0, 0, 0, 0], trimWeight: 1,
            chargeScale: 1),
        RenderingVersion: 2, FolderColorIntensity: 0, SpaceTextColorMode.Automatic, HasCustomAppearance: null);

    public static readonly SpaceTemplate Ordinary = new(isPrivate: false, name: number => $"Space {number}",
        symbol: "square.grid.2x2.fill", accent: number => SpaceAccent.All[(number - 1) % SpaceAccent.All.Count],
        look: accent => accent.House,
        browsing: new(BuiltInSearchEngine.Google, SelectedCustomEngineId: null, [], SearchSuggestionsEnabled: false, CurrentTabCleanup.After12Hours,
            ContentBlockingPolicy.Balanced, KeepsEverything),
        credentials: new(IsEnabled: true, SyncsCrestPasswordsWithICloud: true, AlsoOffersSaveToSystemPasswords: false));

    public static readonly SpaceTemplate Private = new(isPrivate: true, name: number => number == 1 ? "Private" : $"Private {number}",
        symbol: "eyeglasses", accent: _ => SpaceAccent.Indigo, look: _ => PrivateLook,
        browsing: new(BuiltInSearchEngine.DuckDuckGo, SelectedCustomEngineId: null, [], SearchSuggestionsEnabled: false, CurrentTabCleanup.Never,
            ContentBlockingPolicy.Balanced, KeepsEverything),
        credentials: new(IsEnabled: false, SyncsCrestPasswordsWithICloud: false, AlsoOffersSaveToSystemPasswords: false));

    public static IReadOnlyList<SpaceTemplate> All { get; } = [Ordinary, Private];

    #endregion

    #region Variables

    /// Whether this is the template of a private workspace's Spaces.
    public bool IsPrivate { get; }

    /// The symbol a new Space of this template wears.
    public string Symbol => symbol;

    private readonly Func<int, string> name;
    private readonly string symbol;
    private readonly Func<int, SpaceAccent> accent;
    private readonly Func<SpaceAccent, SpaceBranding> look;
    private readonly BrowsingPreferences browsing;
    private readonly CredentialPreferences credentials;

    #endregion

    #region Constructors

    private SpaceTemplate(bool isPrivate, Func<int, string> name, string symbol, Func<int, SpaceAccent> accent,
        Func<SpaceAccent, SpaceBranding> look, BrowsingPreferences browsing, CredentialPreferences credentials) {
        IsPrivate = isPrivate;
        this.name = name;
        this.symbol = symbol;
        this.accent = accent;
        this.look = look;
        this.browsing = browsing;
        this.credentials = credentials;
    }

    #endregion

    #region Actions - Lookup

    /// The template of a private workspace's Spaces, or of an ordinary one's.
    public static SpaceTemplate For(bool privateBrowsing) => All.Single(template => template.IsPrivate == privateBrowsing);

    #endregion

    #region Actions - Spaces

    /// The Space that is `number`th in its workspace, counting from one, with
    /// `profileId` for its profile and one Start Page tab, `tabId`, used at `now`.
    public SpaceState Make(Guid spaceId, Guid profileId, Guid tabId, int number, DateTimeOffset now) {
        ArgumentOutOfRangeException.ThrowIfLessThan(number, 1);
        var shade = accent(number);
        var settings = new SpaceSettings(name(number), symbol, shade, look(shade), browsing, credentials, SpaceAccessPolicy.Open,
            IsSavedTabsExpanded: true, SavedTabsExpansionModifiedAt: null);
        var content = TabKind.StartPage;
        var tab = new TabState(tabId, content.Name, Url: null, NativeContent: null, SavedUrl: null, content.Symbol, FaviconUrl: null,
            IconAccent: null, StoredIconMode: null, TabPlacement.Current, FolderId: null, SplitGroupId: null, now,
            PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null, KeepsPageLoaded: false);
        return new(spaceId, profileId, settings, Folders: [], Tabs: [tab], SplitGroups: [], ArchivedTabs: [], History: []);
    }

    #endregion
}
