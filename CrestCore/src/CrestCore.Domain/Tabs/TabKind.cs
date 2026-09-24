namespace CrestCore.Domain;

/// <summary>The content a tab presents. Persisted native kind names are resolved at the boundary.</summary>
public sealed record TabKind {
    #region Variables

    public string Name { get; }
    public TabRenderType RenderType { get; }
    public string? NativeKind { get; }
    public string Symbol { get; }
    public bool IsStartPage { get; }
    public bool IsWebPage => RenderType == TabRenderType.WebRender && !IsStartPage;
    public static TabKind Web { get; } = new("New tab", TabRenderType.WebRender, null, "globe");
    public static TabKind StartPage { get; } = new("Start Page", TabRenderType.UiNative, null, "flag.fill", true);
    public static TabKind Settings { get; } = new("Settings", TabRenderType.UiNative, "settings", "gearshape");
    public static TabKind GettingStarted { get; } = new("Getting Started", TabRenderType.UiNative, "getting-started", "book.closed.fill");

    #endregion

    #region Constructors

    private TabKind(string name, TabRenderType renderType, string? nativeKind, string symbol, bool isStartPage = false) {
        Name = name;
        RenderType = renderType;
        NativeKind = nativeKind;
        Symbol = symbol;
        IsStartPage = isStartPage;
    }

    #endregion

    #region Actions - Content decoding

    public static TabKind Native(string kind, string title, string symbol = "square") {
        if (string.IsNullOrWhiteSpace(kind)) throw new BrowserRuleException(BrowserRuleCodes.InvalidNativeKind);
        return kind switch {
            "settings" => Settings,
            "getting-started" => GettingStarted,
            _ => new(string.IsNullOrWhiteSpace(title) ? "Native Tab" : title, TabRenderType.UiNative, kind, symbol)
        };
    }

    public static TabKind FromStored(string? nativeKind, string? url, string title)
        => nativeKind is { } kind ? Native(kind, title) : url is null ? StartPage : Web;

    #endregion

    #region Mutators

    public string Title(string? url) => IsWebPage ? url ?? "New tab" : Name;

    #endregion
}
