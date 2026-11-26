using System.Reflection;

namespace CrestCore.Contracts;

/// One of Crest's isolated-world JavaScript content bridges, owned once by the
/// core so every platform and engine (WebKit and Chromium across macOS, iOS,
/// Windows, and Linux) runs the exact same document scripts.
public sealed class ContentBridge {
    #region Static Variables

    private const string ResourcePrefix = "CrestCore.Resources.ContentBridges.";
    private const string TestingHooksToken = "/*__CREST_TESTING_HOOKS__*/";

    /// Cosmetic hiding, procedural filters, empty ad-slot collapsing, and the
    /// element picker.
    public static readonly ContentBridge CosmeticFilter = new(
        name: "cosmetic_filter",
        handlerName: "crestCosmetics",
        mainFrameOnly: false,
        resourceName: "cosmetic-filter.js");

    /// Login, passkey-adjacent, and autofill form detection, filling, and
    /// submission capture.
    public static readonly ContentBridge Credentials = new(
        name: "credentials",
        handlerName: "crestCredentials",
        mainFrameOnly: false,
        resourceName: "credentials.js",
        testingResourceName: "credentials-testing.js");

    /// Reader Mode article detection, extraction, and isolated presentation.
    public static readonly ContentBridge ReaderMode = new(
        name: "reader_mode",
        handlerName: "",
        mainFrameOnly: true,
        resourceName: "reader-mode.js");

    /// Whole-page translation DOM sampling, capture, patching, and restoration.
    public static readonly ContentBridge Translation = new(
        name: "translation",
        handlerName: "",
        mainFrameOnly: true,
        resourceName: "translation.js");

    /// First-contentful-paint notification for dark-mode flash suppression.
    public static readonly ContentBridge FirstPaint = new(
        name: "first_paint",
        handlerName: "crestFirstPaint",
        mainFrameOnly: true,
        resourceName: "first-paint.js");

    public static IReadOnlyList<ContentBridge> All { get; } =
        [CosmeticFilter, Credentials, ReaderMode, Translation, FirstPaint];

    #endregion

    #region Variables

    private readonly string resourceName;
    private readonly string? testingResourceName;
    private readonly Lazy<string> baseSource;
    private readonly Lazy<string>? testingSource;

    public string Name { get; }

    /// The `webkit.messageHandlers` name the bridge posts under, or empty for
    /// evaluated-only bridges.
    public string HandlerName { get; }

    /// Whether the bridge runs only in the page's top document.
    public bool MainFrameOnly { get; }

    #endregion

    #region Constructors

    private ContentBridge(string name, string handlerName, bool mainFrameOnly, string resourceName,
        string? testingResourceName = null) {
        Name = name;
        HandlerName = handlerName;
        MainFrameOnly = mainFrameOnly;
        this.resourceName = resourceName;
        this.testingResourceName = testingResourceName;
        baseSource = new(() => LoadResource(this.resourceName).TrimEnd('\n'));
        testingSource = this.testingResourceName is { } testing
            ? new(() => LoadResource(testing)) : null;
    }

    #endregion

    #region Actions - Lookup

    public static ContentBridge? Named(string? name) => All.FirstOrDefault(bridge => bridge.Name == name);

    #endregion

    #region Actions - Script

    /// Returns this bridge's script, splicing its debug testing hooks when
    /// `includeTestingHooks` is requested and the bridge defines any.
    internal ContentBridgeScript Script(bool includeTestingHooks) {
        var source = baseSource.Value;
        if (testingSource is not null) {
            source = source.Replace(TestingHooksToken, includeTestingHooks ? testingSource.Value : "", StringComparison.Ordinal);
        }
        return new(source, HandlerName, MainFrameOnly);
    }

    private static string LoadResource(string fileName) {
        var assembly = typeof(ContentBridge).Assembly;
        var fullName = ResourcePrefix + fileName;
        using var stream = assembly.GetManifestResourceStream(fullName)
            ?? throw new InvalidOperationException($"Missing embedded content bridge resource '{fullName}'.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    #endregion
}
