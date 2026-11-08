namespace CrestCore.Contracts;

/// A filter list Crest can subscribe to. Each is downloaded from its
/// maintainers at runtime and kept up to date by the core; Crest never ships a
/// copy. Lists use EasyList and uBlock Origin syntax; the AdGuard lists are
/// AdGuard's own builds for uBlock Origin.
///
/// The device store spells a list as its `Name`, so a name never changes. A
/// list travels as its index in `All`, so `All` is append-only.
public sealed class FilterList {
    #region Static Variables

    private const string UBlock = "https://ublockorigin.github.io/uAssets/filters/";
    private const string EasyListDownloads = "https://easylist-downloads.adblockplus.org/";
    private const string AdGuard = "https://filters.adtidy.org/extension/ublock/filters/";

    public static readonly FilterList EasyList = new(name: "easylist", title: "EasyList", FilterListGroup.Ads,
        source: "https://easylist.to/easylist/easylist.txt", isDefault: true);
    public static readonly FilterList EasyPrivacy = new(name: "easyprivacy", title: "EasyPrivacy", FilterListGroup.Ads,
        source: "https://easylist.to/easylist/easyprivacy.txt", isDefault: true);
    public static readonly FilterList UBlockFilters = new(name: "ublock-filters", title: "uBlock filters", FilterListGroup.Ads,
        source: UBlock + "filters.min.txt", isDefault: true);
    public static readonly FilterList UBlockPrivacy = new(name: "ublock-privacy", title: "uBlock filters – Privacy",
        FilterListGroup.Ads, source: UBlock + "privacy.min.txt", isDefault: true);
    public static readonly FilterList UBlockBadware = new(name: "ublock-badware", title: "uBlock filters – Badware risks",
        FilterListGroup.Ads, source: UBlock + "badware.min.txt", isDefault: true);
    public static readonly FilterList UBlockQuickFixes = new(name: "ublock-quick-fixes", title: "uBlock filters – Quick fixes",
        FilterListGroup.Ads, source: UBlock + "quick-fixes.min.txt", isDefault: true);
    public static readonly FilterList UBlockUnbreak = new(name: "ublock-unbreak", title: "uBlock filters – Unbreak",
        FilterListGroup.Ads, source: UBlock + "unbreak.min.txt", isDefault: true);
    public static readonly FilterList AdGuardBase = new(name: "adguard-base", title: "AdGuard Base", FilterListGroup.Ads,
        source: AdGuard + "2_without_easylist.txt");

    public static readonly FilterList EasyListGermany = new(name: "easylist-germany", title: "EasyList Germany",
        FilterListGroup.Regional, source: "https://easylist.to/easylistgermany/easylistgermany.txt", languages: ["de"]);
    public static readonly FilterList ListeFr = new(name: "liste-fr", title: "Liste FR", FilterListGroup.Regional,
        source: EasyListDownloads + "liste_fr.txt", languages: ["fr"]);
    public static readonly FilterList EasyListItaly = new(name: "easylist-italy", title: "EasyList Italy",
        FilterListGroup.Regional, source: EasyListDownloads + "easylistitaly.txt", languages: ["it"]);
    public static readonly FilterList EasyListDutch = new(name: "easylist-dutch", title: "EasyList Dutch",
        FilterListGroup.Regional, source: EasyListDownloads + "easylistdutch.txt", languages: ["nl"]);
    public static readonly FilterList EasyListSpanish = new(name: "easylist-spanish", title: "EasyList Spanish",
        FilterListGroup.Regional, source: EasyListDownloads + "easylistspanish.txt", languages: ["es"]);
    public static readonly FilterList EasyListPolish = new(name: "easylist-polish", title: "EasyList Polish",
        FilterListGroup.Regional, source: EasyListDownloads + "easylistpolish.txt", languages: ["pl"]);
    public static readonly FilterList EasyListChina = new(name: "easylist-china", title: "EasyList China",
        FilterListGroup.Regional, source: EasyListDownloads + "easylistchina.txt", languages: ["zh"]);
    public static readonly FilterList AdGuardJapanese = new(name: "adguard-japanese", title: "AdGuard Japanese",
        FilterListGroup.Regional, source: AdGuard + "7.txt", languages: ["ja"]);
    public static readonly FilterList AdGuardRussian = new(name: "adguard-russian", title: "AdGuard Russian",
        FilterListGroup.Regional, source: AdGuard + "1.txt", languages: ["ru", "uk", "be"]);
    public static readonly FilterList AdGuardTurkish = new(name: "adguard-turkish", title: "AdGuard Turkish",
        FilterListGroup.Regional, source: AdGuard + "13.txt", languages: ["tr"]);

    public static readonly FilterList EasyListCookie = new(name: "easylist-cookie", title: "EasyList Cookie List",
        FilterListGroup.Annoyances, source: "https://secure.fanboy.co.nz/fanboy-cookiemonster_ubo.txt");
    public static readonly FilterList AdGuardAnnoyances = new(name: "adguard-annoyances", title: "AdGuard Annoyances",
        FilterListGroup.Annoyances, source: AdGuard + "14.txt");

    public static IReadOnlyList<FilterList> All { get; } = [
        EasyList, EasyPrivacy, UBlockFilters, UBlockPrivacy, UBlockBadware, UBlockQuickFixes, UBlockUnbreak, AdGuardBase,
        EasyListGermany, ListeFr, EasyListItaly, EasyListDutch, EasyListSpanish, EasyListPolish, EasyListChina,
        AdGuardJapanese, AdGuardRussian, AdGuardTurkish, EasyListCookie, AdGuardAnnoyances
    ];

    #endregion

    #region Variables

    public string Name { get; }

    /// The list's own name, which its maintainers give it.
    public string Title { get; }

    /// Where the settings list it.
    public FilterListGroup Group { get; }

    /// Where its maintainers publish it.
    public string Source { get; }

    /// On unless the person turns it off.
    public bool IsDefault { get; }

    /// The languages, as ISO 639-1 codes, whose readers get a regional list
    /// unless they turn it off.
    public IReadOnlyList<string> Languages { get; }

    #endregion

    #region Constructors

    private FilterList(string name, string title, FilterListGroup group, string source, bool isDefault = false,
        IReadOnlyList<string>? languages = null) {
        Name = name;
        Title = title;
        Group = group;
        Source = source;
        IsDefault = isDefault;
        Languages = languages ?? [];
    }

    #endregion

    #region Actions - Lookup

    public static FilterList? Named(string? name) => All.FirstOrDefault(list => list.Name == name);

    /// Whether a device whose readers prefer `languages`, as BCP 47 tags, has
    /// the list on before the person chooses.
    public bool IsOnByDefault(IReadOnlyList<string> languages) =>
        IsDefault || languages.Any(tag => Languages.Contains(tag.Split('-', '_')[0].ToLowerInvariant()));

    #endregion
}
