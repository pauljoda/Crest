using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Tests;

/// Shared saved-session fixture for the native session, records, sync and
/// maintenance suites, in the shape the Swift encoder writes. It still carries
/// the selection fields older documents stored.
public sealed partial class BrowserContractsTests {
    private static JsonObject SwiftId(Guid value) => new() { ["rawValue"] = value.ToString().ToUpperInvariant() };

    /// The Space a command's selection hint tells its window to show, if any.
    private static Guid? HintedSpace(JsonNode output)
        => output["selection"]!["spaceId"] is { } space ? Guid.Parse(space.GetValue<string>()) : null;

    /// Whether the hint tells the window to show `tab` (null for nothing) in `space`.
    private static bool HintsTab(JsonNode output, Guid space, Guid? tab) => output["selection"]!["tabs"]!.AsArray().Any(entry =>
        Guid.Parse(entry!["spaceId"]!.GetValue<string>()) == space
        && (entry["tabId"] is { } value ? Guid.Parse(value.GetValue<string>()) == tab : tab is null));

    /// A hint that leaves the window's selection exactly as it was.
    private static bool LeavesSelection(JsonNode output)
        => output["selection"]!["spaceId"] is null && output["selection"]!["tabs"]!.AsArray().Count == 0;

    private static Guid SpaceId(JsonNode space) => Guid.Parse(space["id"]!["rawValue"]!.GetValue<string>());

    /// A Space's branding and browsing preferences as the Swift encoder wrote them.
    private const string SavedBranding = """
        {"renderingVersion":5,"bannerPattern":"diagonal","colors":[{"green":0.055,"red":0.235,"blue":0.102,"alpha":1},
        {"green":0.125,"red":0.447,"blue":0.188,"alpha":1}],"gradientAngle":0,"themeMode":"banner","bannerStrength":1,
        "iconStyle":"layeredCrest","readabilityFade":0.45,"textColorMode":"automatic","hasCustomAppearance":false,
        "crest":{"ordinaryColorIndex":1,"divisionCount":4,"symbolColorIndex":1,"chargeWeight":"bold","depth":"none","edgeWidth":0,
        "showsOutline":false,"plateScale":1,"sealTeeth":12,"sheenAngle":45,"symbol":"lion","backplateColorIndex":0,"trimColorIndex":1,
        "edgeColorIndex":1,"trimWeight":0.75,"ordinaryWidth":1,"fieldDivision":"plain","secondaryFieldColorIndex":1,"chargeScale":1.2,
        "trim":"line","finish":"flat","ordinary":"none","backplate":"shield","chargeLayout":"single","chargeOffset":0,"trimDetail":12},
        "folderColorIntensity":0,"keepsControlsReadable":true,"showsTexture":false}
        """;
    private const string SavedBrowsingPreferences = """
        {"contentBlockingPolicy":"balanced","searchSuggestionsEnabled":false,"searchProvider":"duckDuckGo","customSearchProviders":[],
        "selectedSearchProviderID":"duckDuckGo","dataRetention":{"archive":"forever","history":"forever","downloads":"forever"},
        "currentTabCleanupPolicy":"after12Hours"}
        """;
    private static (JsonObject Document, Guid Space, Guid Tab) SavedSession() {
        var space = Guid.NewGuid(); var tab = Guid.NewGuid();
        var folder = Guid.NewGuid();
        JsonObject savedTab = new() {
            ["id"] = SwiftId(tab),
            ["title"] = "Observed page",
            ["url"] = "https://example.com/article#one",
            ["placement"] = "saved",
            ["folderID"] = SwiftId(folder),
            ["savedURL"] = "https://example.com/",
            ["symbol"] = "crest.emoji:🌊",
            ["customTitle"] = "My reading",
            ["lastActivatedAt"] = 800000000.25,
            ["positionModifiedAt"] = 799999999.125,
            ["titleModifiedAt"] = 799999998.75,
            ["splitGroupID"] = SwiftId(Guid.NewGuid()),
            ["keepsPageLoaded"] = true,
            ["faviconURL"] = "https://example.com/favicon.ico",
            ["iconAccent"] = new JsonObject { ["red"] = 0.25, ["green"] = 0.5, ["blue"] = 0.75 }
        };
        JsonObject savedSpace = new() {
            ["id"] = SwiftId(space),
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString().ToUpperInvariant() },
            ["name"] = "Reading",
            ["symbol"] = "book",
            ["accent"] = "teal",
            ["accessPolicy"] = "open",
            ["branding"] = JsonNode.Parse(SavedBranding),
            ["browsingPreferences"] = JsonNode.Parse(SavedBrowsingPreferences),
            ["credentialPreferences"] = new JsonObject {
                ["isEnabled"] = false,
                ["syncsCrestPasswordsWithICloud"] = true,
                ["alsoOffersSaveToSystemPasswords"] = false
            },
            ["isSavedTabsExpanded"] = true,
            ["splitGroups"] = new JsonArray(),
            ["tabs"] = new JsonArray(savedTab),
            ["selectedTabID"] = SwiftId(tab),
            ["folders"] = new JsonArray(new JsonObject {
                ["id"] = SwiftId(folder),
                ["title"] = "Articles",
                ["location"] = "saved",
                ["isCollapsed"] = true,
                ["symbol"] = "book",
                ["color"] = new JsonObject { ["red"] = 0.7 }
            }),
            ["archivedTabs"] = new JsonArray(),
            ["history"] = new JsonArray(new JsonObject {
                ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(),
                ["url"] = "https://example.com/article",
                ["title"] = "Earlier visit",
                ["firstVisitedAt"] = 799999990.0,
                ["lastVisitedAt"] = 800000000.0,
                ["visitCount"] = 4
            })
        };
        return (new JsonObject {
            ["session"] = new JsonObject {
                ["spaces"] = new JsonArray(savedSpace),
                ["selectedSpaceID"] = SwiftId(space),
                ["defaultSpaceID"] = SwiftId(space),
                ["disposableSeedMarker"] = Guid.NewGuid().ToString()
            }
        }, space, tab);
    }
}
