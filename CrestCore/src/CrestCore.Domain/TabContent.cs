namespace CrestCore.Domain;

public enum TabRenderType { WebRender, UiNative }

/// <summary>The content a tab presents. Persisted native kind names are resolved at the boundary.</summary>
public sealed record TabContent {
    private TabContent(string name, TabRenderType renderType, string? nativeKind, string symbol, bool isStartPage = false) {
        Name = name;
        RenderType = renderType;
        NativeKind = nativeKind;
        Symbol = symbol;
        IsStartPage = isStartPage;
    }

    public string Name { get; }
    public TabRenderType RenderType { get; }
    public string? NativeKind { get; }
    public string Symbol { get; }
    public bool IsStartPage { get; }
    public bool IsWebPage => RenderType == TabRenderType.WebRender && !IsStartPage;

    public string Title(string? url) => IsWebPage ? url ?? "New tab" : Name;

    public static TabContent Web { get; } = new("New tab", TabRenderType.WebRender, null, "globe");
    public static TabContent StartPage { get; } = new("Start Page", TabRenderType.UiNative, null, "flag.fill", true);
    public static TabContent Settings { get; } = new("Settings", TabRenderType.UiNative, "settings", "gearshape");
    public static TabContent GettingStarted { get; } = new("Getting Started", TabRenderType.UiNative, "getting-started", "book.closed.fill");

    public static TabContent Native(string kind, string title, string symbol = "square") {
        if (string.IsNullOrWhiteSpace(kind)) throw new BrowserRuleException("invalid_native_kind");
        return kind switch {
            "settings" => Settings,
            "getting-started" => GettingStarted,
            _ => new(string.IsNullOrWhiteSpace(title) ? "Native Tab" : title, TabRenderType.UiNative, kind, symbol)
        };
    }

    public static TabContent FromStored(string? nativeKind, string? url, string title)
        => nativeKind is { } kind ? Native(kind, title) : url is null ? StartPage : Web;
}
