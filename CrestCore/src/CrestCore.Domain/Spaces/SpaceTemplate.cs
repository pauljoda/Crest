using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a new Space starts as in each kind of workspace: its name, symbol,
/// accent and look, what it searches and keeps, and whether it offers to save
/// passwords. Every new Space has a profile of its own and one Start Page tab,
/// and opens freely. An ordinary Space takes the next accent in turn and wears
/// the house palette that accent names; a private one wears the private look
/// and never offers to save or sync passwords.
public sealed class SpaceTemplate {
    #region Static Variables

    /// A new Space keeps what it browses until the person chooses otherwise.
    private static readonly DataRetentionPreferences KeepsEverything = new(DataRetention.Forever, DataRetention.Forever,
        DataRetention.Forever);

    /// The house palette each accent names: a deep field, a related tincture a
    /// step above it and one luminous charge, with the crest composed for it.
    /// A palette is copied into the Space, which keeps it when this changes.
    private static readonly Dictionary<SpaceAccent, SpaceBranding> HouseLooks = new() {
        // Winter.
        [SpaceAccent.Indigo] = House([new(0.118, 0.157, 0.200), new(0.243, 0.306, 0.369), new(0.525, 0.678, 0.769)],
            CrestBackplate.FrenchShield, CrestSymbol.Direwolf, CrestTrim.Line),
        // Sun.
        [SpaceAccent.Orange] = House([new(0.208, 0.086, 0.043), new(0.545, 0.239, 0.106), new(0.816, 0.620, 0.396)],
            CrestBackplate.Circle, CrestSymbol.Sun, CrestTrim.Sunburst),
        // Meadow.
        [SpaceAccent.Teal] = House([new(0.082, 0.137, 0.094), new(0.204, 0.341, 0.220), new(0.737, 0.655, 0.400)],
            CrestBackplate.Circle, CrestSymbol.Rose, CrestTrim.Laurel),
        // Lion.
        [SpaceAccent.Rose] = House([new(0.235, 0.055, 0.102), new(0.447, 0.125, 0.188), new(0.788, 0.635, 0.329)],
            CrestBackplate.Shield, CrestSymbol.Lion, CrestTrim.Line)
    };

    /// The one purple a private Space wears, with a plain key for its symbol.
    private static readonly SpaceBranding PrivateLook = new(new([new(0.58, 0.30, 0.76)]), SpaceBannerPattern.Solid,
        BannerStrength: 1, ReadabilityFade: 1, KeepsControlsReadable: true, SpaceThemeMode.Banner, GradientAngle: 0,
        ShowsTexture: false, SpaceIconStyle.SimpleSymbol, SymbolColor: null,
        Crest(CrestBackplate.None, CrestSymbol.Key, CrestTrim.None, layers: [0, 0, 0, 0, 0, 0], trimWeight: 1, chargeScale: 1),
        RenderingVersion: 2, FolderColorIntensity: 0, SpaceTextColorMode.Automatic, HasCustomAppearance: null);

    public static readonly SpaceTemplate Ordinary = new(isPrivate: false, name: number => $"Space {number}",
        symbol: "square.grid.2x2.fill", accent: number => Enum.GetValues<SpaceAccent>()[(number - 1) % Enum.GetValues<SpaceAccent>().Length],
        look: accent => HouseLooks[accent],
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

    /// A house palette's branding: a diagonal banner that keeps controls
    /// readable, and the layered crest drawn in the palette's own colors.
    private static SpaceBranding House(BrandColor[] colors, CrestBackplate backplate, CrestSymbol figure, CrestTrim trim) =>
        new(new(colors), SpaceBannerPattern.Diagonal, BannerStrength: 1, ReadabilityFade: 0.45, KeepsControlsReadable: true,
            SpaceThemeMode.Banner, GradientAngle: 0, ShowsTexture: false, SpaceIconStyle.LayeredCrest, SymbolColor: null,
            Crest(backplate, figure, trim, layers: [0, 1, 1, 2, 2, 2], trimWeight: 0.75, chargeScale: 1.2),
            RenderingVersion: 5, FolderColorIntensity: 0, SpaceTextColorMode.Automatic, HasCustomAppearance: false);

    /// A plain-field crest with no ordinary. `layers` addresses the backplate,
    /// the second field, the ordinary, the trim, the figure and the edge.
    private static SpaceCrest Crest(CrestBackplate backplate, CrestSymbol figure, CrestTrim trim, int[] layers, double trimWeight,
        double chargeScale) =>
        new(backplate, CrestFieldDivision.Plain, CrestOrdinary.None, trim, figure, CrestChargeLayout.Single,
            BackplateColorIndex: layers[0], SecondaryFieldColorIndex: layers[1], OrdinaryColorIndex: layers[2], TrimColorIndex: layers[3],
            SymbolColorIndex: layers[4], StartingPresetId: null, EdgeColorIndex: layers[5], Palette: null, Charge: null, PlateScale: 1,
            EdgeWidth: 0, DivisionCount: 4, CrestFinish.Flat, OrdinaryWidth: 1, trimWeight, TrimDetail: 12, chargeScale, ChargeOffset: 0,
            CrestChargeWeight.Bold, SheenAngle: 45, SealTeeth: 12, ShowsOutline: false, CrestDepth.None);

    #endregion
}
