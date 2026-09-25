using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The look a Space wears, which the core resolves for every platform. The
/// expected values are what the Swift bridge produced before the look moved
/// into the core, read through the stored format the Swift encoder writes.
public sealed class SpaceLookTests {
    #region Static Variables

    /// `BrowserSpaceBranding.legacy(accent: .indigo, symbol: "folder")`, as Swift encoded it.
    private const string LegacyIndigoFolder = """
        {"bannerPattern":"diagonal","bannerStrength":1,"colors":[{"alpha":1,"blue":0.23,"green":0.15,"red":0.08},
        {"alpha":1,"blue":0.64,"green":0.42,"red":0.22},{"alpha":1,"blue":0.25,"green":0.67,"red":0.88}],"crest":{"backplate":"shield",
        "backplateColorIndex":1,"chargeLayout":"single","chargeOffset":0,"chargeScale":1,"chargeWeight":"bold","depth":"none",
        "divisionCount":4,"edgeColorIndex":1,"edgeWidth":0,"fieldDivision":"plain","finish":"flat","ordinary":"none","ordinaryColorIndex":2,
        "ordinaryWidth":1,"plateScale":1,"sealTeeth":12,"secondaryFieldColorIndex":1,"sheenAngle":45,"showsOutline":false,"symbol":"mountain",
        "symbolColorIndex":2,"trim":"none","trimColorIndex":1,"trimDetail":12,"trimWeight":1},"folderColorIntensity":0,"gradientAngle":0,
        "iconStyle":"simpleSymbol","keepsControlsReadable":true,"readabilityFade":0.25,"renderingVersion":2,"showsTexture":false,
        "textColorMode":"automatic","themeMode":"banner"}
        """;

    /// `BrowserSpaceBranding.initial(accent: .indigo, symbol:)`, the Winter house look, as Swift encoded it.
    private const string HouseIndigo = """
        {"bannerPattern":"diagonal","bannerStrength":1,"colors":[{"alpha":1,"blue":0.2,"green":0.157,"red":0.118},
        {"alpha":1,"blue":0.369,"green":0.306,"red":0.243},{"alpha":1,"blue":0.769,"green":0.678,"red":0.525}],"crest":{
        "backplate":"frenchShield","backplateColorIndex":0,"chargeLayout":"single","chargeOffset":0,"chargeScale":1.2,"chargeWeight":"bold",
        "depth":"none","divisionCount":4,"edgeColorIndex":2,"edgeWidth":0,"fieldDivision":"plain","finish":"flat","ordinary":"none",
        "ordinaryColorIndex":1,"ordinaryWidth":1,"plateScale":1,"sealTeeth":12,"secondaryFieldColorIndex":1,"sheenAngle":45,
        "showsOutline":false,"symbol":"direwolf","symbolColorIndex":2,"trim":"line","trimColorIndex":2,"trimDetail":12,"trimWeight":0.75},
        "folderColorIntensity":0,"gradientAngle":0,"hasCustomAppearance":false,"iconStyle":"layeredCrest","keepsControlsReadable":true,
        "readabilityFade":0.45,"renderingVersion":5,"showsTexture":false,"textColorMode":"automatic","themeMode":"banner"}
        """;

    /// Each accent's legacy palette and house look, as Swift drew them, where they
    /// differ from indigo's.
    public static TheoryData<string, string, string, string, string, string> Accents => new() {
        { "indigo", """[{"red":0.08,"green":0.15,"blue":0.23},{"red":0.22,"green":0.42,"blue":0.64},{"red":0.88,"green":0.67,"blue":0.25}]""",
            """[{"red":0.118,"green":0.157,"blue":0.2},{"red":0.243,"green":0.306,"blue":0.369},{"red":0.525,"green":0.678,"blue":0.769}]""",
            "frenchShield", "direwolf", "line" },
        { "orange", """[{"red":0.85,"green":0.27,"blue":0.2},{"red":0.88,"green":0.67,"blue":0.25},{"red":0.22,"green":0.42,"blue":0.64}]""",
            """[{"red":0.208,"green":0.086,"blue":0.043},{"red":0.545,"green":0.239,"blue":0.106},{"red":0.816,"green":0.62,"blue":0.396}]""",
            "circle", "sun", "sunburst" },
        { "teal", """[{"red":0.12,"green":0.49,"blue":0.52},{"red":0.22,"green":0.42,"blue":0.64},{"red":0.82,"green":0.72,"blue":0.56}]""",
            """[{"red":0.082,"green":0.137,"blue":0.094},{"red":0.204,"green":0.341,"blue":0.22},{"red":0.737,"green":0.655,"blue":0.4}]""",
            "circle", "rose", "laurel" },
        { "rose", """[{"red":0.72,"green":0.25,"blue":0.42},{"red":0.29,"green":0.25,"blue":0.58},{"red":0.82,"green":0.72,"blue":0.56}]""",
            """[{"red":0.235,"green":0.055,"blue":0.102},{"red":0.447,"green":0.125,"blue":0.188},{"red":0.788,"green":0.635,"blue":0.329}]""",
            "shield", "lion", "line" }
    };

    #endregion

    #region Actions - Legacy looks

    /// A Space stored before branding existed wears the look Swift gave it: the
    /// accent's legacy palette in a full-strength diagonal banner and a plain shield,
    /// and each accent's house look is the one Swift's `initial` drew.
    [Theory]
    [MemberData(nameof(Accents))]
    public void EachAccentWearsTheLegacyAndHouseLooksSwiftDrew(string name, string legacyColors, string houseColors, string backplate,
        string figure, string trim) {
        var accent = Assert.IsType<SpaceAccent>(SpaceAccent.Named(name));
        var legacy = JsonNode.Parse(LegacyIndigoFolder)!;
        legacy["colors"] = JsonNode.Parse(legacyColors);
        var house = JsonNode.Parse(HouseIndigo)!;
        house["colors"] = JsonNode.Parse(houseColors);
        house["crest"]!["backplate"] = backplate;
        house["crest"]!["symbol"] = figure;
        house["crest"]!["trim"] = trim;

        Assert.Equal(StoredSessionCodec.DecodeBranding(legacy), SpaceBranding.Legacy(accent, "folder"));
        Assert.Equal(StoredSessionCodec.DecodeBranding(house), accent.House);
    }

    /// The legacy crest's figure is the one a keyword of the Space's SF Symbol
    /// suggested to Swift, and a mountain otherwise.
    [Theory]
    [InlineData("folder", "mountain")]
    [InlineData("leaf.fill", "leaf")]
    [InlineData("book.closed", "book")]
    [InlineData("graduationcap", "book")]
    [InlineData("key.fill", "key")]
    [InlineData("flame", "flame")]
    [InlineData("compass.drawing", "compass")]
    [InlineData("location.north", "compass")]
    [InlineData("sun.max", "sun")]
    [InlineData("safari", "mountain")]
    [InlineData("globe", "mountain")]
    [InlineData("eyeglasses", "mountain")]
    public void TheLegacyCrestCarriesTheFigureItsSymbolSuggested(string symbol, string figure) {
        var expected = JsonNode.Parse(LegacyIndigoFolder)!;
        expected["crest"]!["symbol"] = figure;

        Assert.Equal(StoredSessionCodec.DecodeBranding(expected), SpaceBranding.Legacy(SpaceAccent.Indigo, symbol));
    }

    #endregion

    #region Actions - Worn looks

    /// A Space with branding wears it, with a banner strength stored before the
    /// baseline vocabulary in today's units, as Swift converted it; a Space without
    /// branding wears its accent's legacy look.
    [Theory]
    [InlineData(1, 0.0, 0.72)]
    [InlineData(1, 0.25, 0.79)]
    [InlineData(1, 0.5, 0.86)]
    [InlineData(1, 0.8, 0.944)]
    [InlineData(1, 1.0, 1.0)]
    [InlineData(1, 1.4, 1.0)]
    [InlineData(1, -0.2, 0.6639999999999999)]
    [InlineData(0, 0.5, 0.86)]
    [InlineData(2, 0.5, 0.5)]
    [InlineData(5, 0.25, 0.25)]
    [InlineData(5, 1.4, 1.4)]
    public void ASpaceWearsItsBrandingInTodaysUnits(int version, double stored, double worn) {
        var branding = SpaceAccent.Teal.House with { RenderingVersion = version, BannerStrength = stored };
        var settings = Settings(SpaceAccent.Teal, "globe", branding);

        Assert.Equal(worn, settings.Look.BannerStrength);
        Assert.Equal(Math.Max(version, SpaceBranding.BaselineRenderingVersion), settings.Look.RenderingVersion);
        Assert.Equal(branding with { BannerStrength = worn, RenderingVersion = settings.Look.RenderingVersion }, settings.Look);
        Assert.Equal(SpaceBranding.Legacy(SpaceAccent.Rose, "key"), Settings(SpaceAccent.Rose, "key", branding: null).Look);
    }

    private static SpaceSettings Settings(SpaceAccent accent, string symbol, SpaceBranding? branding) =>
        new("Look", symbol, accent, branding, StoredSessionCodec.DefaultBrowsingPreferences, StoredSessionCodec.DefaultCredentialPreferences,
            SpaceAccessPolicy.Open, IsSavedTabsExpanded: true, SavedTabsExpansionModifiedAt: null);

    #endregion
}
