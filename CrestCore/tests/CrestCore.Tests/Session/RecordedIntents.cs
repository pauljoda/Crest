using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Tests;

/// A clock a test sets.
internal sealed class TestClock(DateTimeOffset now) : IClock {
    #region Variables

    public DateTimeOffset Now { get; set; } = now;

    #endregion
}

/// The identities a test supplied, in order, and fresh ones once they run out.
internal sealed class TestIds : IIdSource {
    #region Variables

    private readonly Queue<Guid> supplied = [];

    #endregion

    #region Actions - Identity supply

    public void Supply(IEnumerable<Guid> ids) {
        foreach (var id in ids) supplied.Enqueue(id);
    }

    public Guid Next() => supplied.TryDequeue(out var id) ? id : Guid.NewGuid();

    #endregion
}

/// A recorded `history.visit`, which a page's engine reports now: a document
/// in the Space `SpaceId` finished at `Url`, titled `Title`, at `At`.
internal sealed record RecordedNavigation(Guid SpaceId, string Url, string Title, DateTimeOffset At);

/// The recorded session commands whose operations are typed intents or engine
/// reports now. A recorded step keeps the request the command sent, so the
/// step runs as what replaced it, at the time the request names.
internal static class RecordedIntents {
    #region Actions - Reading

    /// The intents a recorded request became, issued in `workspace` from
    /// `window` against the session `current` holds, or null for a request
    /// that is still a session command. A recorded Space creation carried the
    /// look the Space started with, which the core now picks itself, so it
    /// becomes the creation and the edits that dress the new Space as the
    /// recording did.
    public static IReadOnlyList<SessionIntent>? Typed(JsonObject request, Guid workspace, Guid? window, SessionState current) {
        var arguments = request["arguments"] as JsonObject ?? [];
        Guid Id(string key) => Guid.Parse(request[key]!.GetValue<string>());
        Guid Argument(string key) => Guid.Parse(arguments[key]!.GetValue<string>());
        Guid? Optional(string key) => arguments[key] is { } value ? Guid.Parse(value.GetValue<string>()) : null;
        BrandColor? Color(JsonNode? value) => value is JsonObject color ? StoredSessionCodec.DecodeColor(color) : null;
        string Text(string key) => arguments[key]!.GetValue<string>();
        return request["operation"]!.GetValue<string>() switch {
            "tab.open" => [Opening(workspace, window ?? Guid.Empty, Id("spaceId"), arguments)],
            "tab.close" => [new CloseTab(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"))],
            "archive.restore" => [new RestoreArchivedTab(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"))],
            "records.sweep" => [new SweepExpiredRecords(workspace)],
            "folder.create" => [new CreateFolder(workspace, Id("spaceId"), Argument("folderId"),
                TabPlacement.Named(Text("placement"))!, Optional("parentId"), arguments["title"]?.GetValue<string>(),
                Color(arguments["color"]), arguments["symbol"]?.GetValue<string>(),
                [.. (arguments["tabIds"] as JsonArray ?? []).Select(id => Guid.Parse(id!.GetValue<string>()))],
                arguments["detach"]?.GetValue<bool>() == true)],
            "split.join" => [new JoinSplit(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"), Argument("targetId"),
                arguments["index"]?.GetValue<int>(), [.. (arguments["copyObservations"] as JsonArray ?? []).Select(page =>
                    new SourcePage(Guid.Parse(page!["tabId"]!.GetValue<string>()), page["url"]?.GetValue<string>(),
                        page["title"]!.GetValue<string>()))])],
            "split.title" => [new NameSplit(workspace, Id("spaceId"), Argument("groupId"), arguments["value"]?.GetValue<string>())],
            "split.tint" => [new TintSplit(workspace, Id("spaceId"), Argument("groupId"), Color(arguments["value"]))],
            "space.identity" => [new SetSpaceIdentity(workspace, Id("spaceId"), Text("name"), Text("symbol"),
                StoredSessionCodec.ParseAccent(Text("accent"))!.Value)],
            "space.saved_expansion" => [new ExpandSavedTabs(workspace, Id("spaceId"), arguments["value"]!.GetValue<bool>())],
            "space.branding" => [new SetSpaceBranding(workspace, Id("spaceId"), StoredSessionCodec.DecodeBranding(arguments["value"]))],
            "space.credential_preferences" => [new SetCredentialPreferences(workspace, Id("spaceId"),
                StoredSessionCodec.DecodeCredentialPreferences(arguments["value"]))],
            "space.access" => [new SetSpaceAccess(workspace, Id("spaceId"), StoredSessionCodec.ParseAccessPolicy(Text("value"))!.Value)],
            "space.default" => [new SetDefaultSpace(workspace, Id("spaceId"))],
            "space.reorder" => [new ReorderSpaces(workspace, Moved([.. current.Spaces.Select(space => space.Id)],
                [.. arguments["offsets"]!.AsArray().Select(offset => offset!.GetValue<int>())], arguments["destination"]!.GetValue<int>()))],
            "space.create" => Created(workspace, window ?? Guid.Empty, StoredSessionCodec.DecodeSpace(arguments["template"]), current),
            "space.deletion.begin" => [new BeginDeletingSpace(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("operationID"))],
            "space.remove" => [new FinishDeletingSpace(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("operationID"))],
            _ => null
        };
    }

    /// The tab a recorded `tab.open` gave the core whole, opened as the intent
    /// that names what it shows.
    private static OpenTab Opening(Guid workspace, Guid window, Guid space, JsonObject arguments) {
        var tab = StoredSessionCodec.DecodeTab(arguments["tab"]);
        return new(workspace, window, space, tab.Id, new TabContent(tab.Url, tab.NativeContent, tab.Title, tab.Symbol), tab.Placement,
            arguments["after"] is { } after ? Guid.Parse(after.GetValue<string>()) : null, arguments["select"]?.GetValue<bool>() == true);
    }

    /// The navigation a recorded `history.visit` stands for, or null for any
    /// other request.
    public static RecordedNavigation? Navigation(JsonObject request) {
        if (request["operation"]!.GetValue<string>() != "history.visit") return null;
        var arguments = request["arguments"]!.AsObject();
        return new(Guid.Parse(request["spaceId"]!.GetValue<string>()), arguments["url"]!.GetValue<string>(),
            arguments["title"]?.GetValue<string>() ?? "", Time(request));
    }

    /// An engine for recorded navigations' pages, which does what the core asks.
    public static Engine PageEngine(CrestApp app) =>
        app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true), _ => { });

    /// Reports `navigation` from a page `engine` hosts in `window` for no tab,
    /// as a Quick Window's page does, and answers the changes the core
    /// published, through the page's release.
    public static IReadOnlyList<Change> Report(CrestApp app, Engine engine, RecordedNavigation navigation, Guid workspace, Guid window) {
        var page = Guid.NewGuid();
        var changes = new List<Change>(app.Send(new OpenPage(page, workspace, navigation.SpaceId, null, window)));
        app.Report(engine, new PageCreated(page));
        app.Report(engine, new NavigationStarted(page, navigation.Url, SameDocument: false));
        app.Report(engine, new NavigationCommitted(page, navigation.Url, SameDocument: false));
        app.Report(engine, new NavigationFinished(page, navigation.Url, navigation.Title));
        changes.AddRange(app.Send(new ReleasePage(page, KeepsState: false)));
        return changes;
    }

    /// The Spaces a recorded reorder left, which moved the ones at `offsets`
    /// to before the one at `destination`, as a list's move does.
    private static IReadOnlyList<Guid> Moved(IReadOnlyList<Guid> spaces, IReadOnlyList<int> offsets, int destination) {
        var moving = offsets.Distinct().Order().ToArray();
        var staying = spaces.Where((_, index) => !moving.Contains(index)).ToList();
        staying.InsertRange(destination - moving.Count(index => index < destination), moving.Select(index => spaces[index]));
        return staying;
    }

    /// A recorded creation as the core makes it, then renamed, dressed and
    /// protected as the recorded template was. The core names the Space
    /// itself, as it did then.
    private static IReadOnlyList<SessionIntent> Created(Guid workspace, Guid window, SpaceState template, SessionState current) => [
        new CreateSpace(workspace, window, template.Id),
        new SetSpaceIdentity(workspace, template.Id, $"Space {current.Spaces.Count + 1}", template.Settings.Symbol, template.Settings.Accent),
        new SetSpaceBranding(workspace, template.Id, template.Settings.Branding!),
        new SetCredentialPreferences(workspace, template.Id, template.Settings.CredentialPreferences)
    ];

    /// TRANSITIONAL until browsing preferences are an intent: the command a
    /// recorded Space creation still needs after its intents, which gives
    /// the new Space the browsing preferences its template carried.
    public static JsonObject? FollowingCommand(JsonObject request) {
        if (request["operation"]!.GetValue<string>() != "space.create") return null;
        var template = request["arguments"]!["template"]!;
        return new JsonObject {
            ["version"] = 1,
            ["operation"] = "space.browsing_preferences",
            ["spaceId"] = template["id"]!["rawValue"]!.GetValue<string>(),
            ["profileId"] = template["profile"]!["id"]!.GetValue<string>(),
            ["arguments"] = new JsonObject { ["value"] = template["browsingPreferences"]!.DeepClone() },
            ["now"] = request["now"]!.DeepClone()
        };
    }

    /// The identities a recorded request gave the records it made, which the
    /// core now gives them itself: a copy's, or a new Space's profile and tab.
    public static IEnumerable<Guid> Identities(JsonObject request) {
        if (request["arguments"]?["template"] is JsonObject template)
            return [Guid.Parse(template["profile"]!["id"]!.GetValue<string>()),
                Guid.Parse(template["tabs"]![0]!["id"]!["rawValue"]!.GetValue<string>())];
        return (request["arguments"]?["ids"] as JsonArray ?? []).Select(id => Guid.Parse(id!.GetValue<string>()));
    }

    /// When a recorded request ran.
    public static DateTimeOffset Time(JsonObject request) => StoredSessionCodec.Date(request["now"]!.GetValue<double>());

    #endregion
}
