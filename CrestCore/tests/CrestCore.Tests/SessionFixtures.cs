using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Tests;

/// Shared saved-session fixture for the native session, records, sync and
/// maintenance suites. It intentionally carries unknown additive fields.
public sealed partial class BrowserContractsTests {
    private static JsonObject SwiftId(Guid value) => new() { ["rawValue"] = value.ToString().ToUpperInvariant() };
    private static (JsonObject Document, SpaceId Space, TabId Tab, WindowId Window) SavedSession(bool empty = false) {
        var space = new SpaceId(Guid.NewGuid()); var tab = new TabId(Guid.NewGuid()); var window = new WindowId(Guid.NewGuid());
        var folder = Guid.NewGuid();
        JsonObject savedTab = new() {
            ["id"] = SwiftId(tab.Value),
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
            ["iconAccent"] = new JsonObject { ["future"] = "blue" },
            ["futureTabProperty"] = new JsonArray(1, 2, 3)
        };
        JsonObject savedSpace = new() {
            ["id"] = SwiftId(space.Value),
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString().ToUpperInvariant() },
            ["name"] = "Reading",
            ["symbol"] = "book",
            ["accent"] = "future-accent",
            ["accessPolicy"] = "open",
            ["branding"] = new JsonObject { ["inactivePalette"] = "preserve-me" },
            ["browsingPreferences"] = new JsonObject { ["searchProvider"] = "duckDuckGo", ["futureFlag"] = true },
            ["credentialPreferences"] = new JsonObject { ["isEnabled"] = false },
            ["tabs"] = new JsonArray(savedTab),
            ["selectedTabID"] = SwiftId(tab.Value),
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
                ["visitCount"] = 4,
                ["futureHistoryProperty"] = true
            })
        };
        JsonObject savedWindow = new() {
            ["id"] = SwiftId(window.Value),
            ["selectedSpaceID"] = SwiftId(space.Value),
            ["selectedTabIDsBySpace"] = empty ? new JsonArray() : new JsonArray(SwiftId(space.Value), SwiftId(tab.Value)),
            ["capturedSpaceIDs"] = new JsonArray(SwiftId(space.Value)),
            ["sidebarWidth"] = 271.5,
            ["extensionSidebarBySpace"] = new JsonArray(SwiftId(space.Value), new JsonObject { ["width"] = 300 })
        };
        return (new JsonObject {
            ["workspaceId"] = Guid.NewGuid().ToString(),
            ["formatVersion"] = 1,
            ["session"] = new JsonObject {
                ["spaces"] = new JsonArray(savedSpace),
                ["selectedSpaceID"] = SwiftId(space.Value),
                ["defaultSpaceID"] = SwiftId(space.Value),
                ["disposableSeedMarker"] = Guid.NewGuid().ToString(),
                ["futureSessionProperty"] = "survives"
            },
            ["windows"] = new JsonArray(savedWindow)
        }, space, tab, window);
    }
}
